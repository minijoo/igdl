"""Tests for the async resolve pipeline in instagram.py — specifically the
disconnect-checking and lock-serialization behavior added after a real
report: force-quitting the app doesn't reliably close the underlying
connection, so the backend needed to check for client disconnection itself
rather than trusting it'll always find out. No real network/Instagram
calls happen here — instaloader.Post.from_shortcode and
comments_graphql.fetch_top_comments are both mocked.

Run with: .venv/bin/python3 -m unittest app.test_instagram -v
(from the backend/ directory)
"""
import asyncio
import time
import unittest
from unittest.mock import MagicMock, patch

from app import instagram


class FakeRequest:
    """Stands in for starlette's Request — is_disconnected() returns False
    for the first `disconnect_after_call` calls, then True forever after,
    so a test can control exactly which disconnect check (if any) should
    catch it.
    """

    def __init__(self, disconnect_after_call: int = -1):
        self._disconnect_after_call = disconnect_after_call
        self.call_count = 0

    async def is_disconnected(self) -> bool:
        self.call_count += 1
        if self._disconnect_after_call < 0:
            return False
        return self.call_count > self._disconnect_after_call


def make_fake_post(is_video: bool = True) -> MagicMock:
    post = MagicMock()
    post.is_video = is_video
    post.mediaid = 123
    post.video_url = "https://cdn.example.com/video.mp4"
    post.url = "https://cdn.example.com/cover.jpg"
    post.caption = "hello"
    return post


class ResolvePostTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        # Deterministic and fast — the real env-configured breather isn't
        # what's under test here.
        instagram._MIN_GAP_SECONDS = 0.0
        instagram._MAX_GAP_SECONDS = 0.0
        instagram._last_call_finished_at = 0.0

    async def test_resolves_successfully_when_client_stays_connected(self):
        post = make_fake_post()
        with patch("instaloader.Post.from_shortcode", return_value=post), \
                patch("app.comments_graphql.fetch_top_comments", return_value=[]):
            result = await instagram.resolve_post(FakeRequest(), "abc123")

        self.assertEqual(result["short_code"], "abc123")
        self.assertEqual(result["video_url"], post.video_url)

    async def test_raises_before_any_instagram_call_if_already_disconnected(self):
        with patch("instaloader.Post.from_shortcode") as from_shortcode:
            with self.assertRaises(instagram.ResolveError):
                await instagram.resolve_post(FakeRequest(disconnect_after_call=0), "abc123")
            from_shortcode.assert_not_called()

    async def test_raises_after_breather_if_disconnected_during_it(self):
        instagram._MIN_GAP_SECONDS = 0.05
        instagram._MAX_GAP_SECONDS = 0.05
        # 1st is_disconnected() call is right after acquiring the lock
        # (should be False), 2nd is after the breather (should trip this).
        with patch("instaloader.Post.from_shortcode") as from_shortcode:
            with self.assertRaises(instagram.ResolveError):
                await instagram.resolve_post(FakeRequest(disconnect_after_call=1), "abc123")
            from_shortcode.assert_not_called()

    async def test_lock_serializes_concurrent_resolves(self):
        order = []

        def slow_from_shortcode(context, short_code):
            order.append(f"start-{short_code}")
            time.sleep(0.05)
            order.append(f"end-{short_code}")
            return make_fake_post()

        with patch("instaloader.Post.from_shortcode", side_effect=slow_from_shortcode), \
                patch("app.comments_graphql.fetch_top_comments", return_value=[]):
            await asyncio.gather(
                instagram.resolve_post(FakeRequest(), "a"),
                instagram.resolve_post(FakeRequest(), "b"),
            )

        # If the lock genuinely serialized these, one's start/end pair can
        # never interleave with the other's — no "start-a, start-b, end-a".
        self.assertIn(order, [
            ["start-a", "end-a", "start-b", "end-b"],
            ["start-b", "end-b", "start-a", "end-a"],
        ])

    async def test_raises_after_from_shortcode_if_disconnected_during_it(self):
        # 1st is_disconnected() call: right after lock. 2nd: after breather.
        # 3rd: right after from_shortcode returns — this is the one under
        # test, catching a disconnect that happened while that (potentially
        # multi-second) call was running.
        post = make_fake_post()
        with patch("instaloader.Post.from_shortcode", return_value=post), \
                patch("app.comments_graphql.fetch_top_comments") as fetch_comments:
            with self.assertRaises(instagram.ResolveError):
                await instagram.resolve_post(FakeRequest(disconnect_after_call=2), "abc123")
            fetch_comments.assert_not_called()

    async def test_no_video_still_raises_after_successful_lookup(self):
        post = make_fake_post(is_video=False)
        with patch("instaloader.Post.from_shortcode", return_value=post):
            with self.assertRaises(instagram.ResolveError) as ctx:
                await instagram.resolve_post(FakeRequest(), "abc123")
        self.assertEqual(str(ctx.exception), "post has no video")

    async def test_error_reading_lazy_post_field_is_a_resolve_error(self):
        # Post.video_url can make its own Instagram request; a challenge
        # raised from it once escaped resolve_post's error handling as an
        # unhandled exception (a 500) instead of a ResolveError (a 502).
        import instaloader

        post = make_fake_post()
        type(post).video_url = property(lambda self: (_ for _ in ()).throw(
            instaloader.exceptions.AbortDownloadException("challenge_required")))
        with patch("instaloader.Post.from_shortcode", return_value=post), \
                patch("app.comments_graphql.fetch_top_comments") as fetch_comments:
            with self.assertRaises(instagram.ResolveError) as ctx:
                await instagram.resolve_post(FakeRequest(), "abc123")
            fetch_comments.assert_not_called()
        self.assertIn("challenge_required", str(ctx.exception))

    async def test_comments_fetch_error_degrades_to_empty_list_not_failure(self):
        from app.comments_graphql import CommentsFetchError

        post = make_fake_post()
        with patch("instaloader.Post.from_shortcode", return_value=post), \
                patch("app.comments_graphql.fetch_top_comments", side_effect=CommentsFetchError("429")):
            result = await instagram.resolve_post(FakeRequest(), "abc123")

        self.assertEqual(result["comments"], [])


if __name__ == "__main__":
    unittest.main()
