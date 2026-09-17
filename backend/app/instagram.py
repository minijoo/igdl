import logging
import random
import threading
import time

import instaloader

from . import comments_graphql
from .config import SESSION_USERNAME

logger = logging.getLogger("igdl.resolve")

# One shared, already-authenticated Instaloader instance for the process's
# lifetime rather than re-loading the session file per request — cheap to
# share since every Instagram-facing call goes through _lock below anyway.
_loader = instaloader.Instaloader()
_loader.load_session_from_file(SESSION_USERNAME)
_lock = threading.Lock()

# The lock above only ever prevented *concurrent* Instagram-facing calls —
# the instant one resolve released it, the next queued one fired
# immediately, with zero gap. That's a suspiciously regular, zero-jitter
# request pattern regardless of how "slow" any single call is, and is
# suspected of contributing to the account periodically needing
# re-authentication (a real session was replaced via update_session.sh after
# ~100 downloads in an hour triggered this). A randomized pause between
# resolves — not a fixed one, so the spacing itself doesn't become the next
# tell — gives Instagram's traffic a breather between posts even when
# requests are queued back-to-back. Tune these if it's still not enough, or
# loosen them if batches end up taking too long in practice.
_MIN_GAP_SECONDS = 2.0
_MAX_GAP_SECONDS = 5.0
_last_call_finished_at = 0.0


class ResolveError(Exception):
    pass


def _wait_for_breather() -> None:
    """Sleeps just long enough (if at all) that at least a random
    [_MIN_GAP_SECONDS, _MAX_GAP_SECONDS) interval has passed since the last
    Instagram-facing call actually finished. Must be called while already
    holding _lock — this reads/writes _last_call_finished_at with no
    separate locking of its own.
    """
    elapsed = time.monotonic() - _last_call_finished_at
    gap = random.uniform(_MIN_GAP_SECONDS, _MAX_GAP_SECONDS)
    if elapsed < gap:
        pause = gap - elapsed
        logger.info("resolve pausing before Instagram call pause=%.1fs", pause)
        time.sleep(pause)


def resolve_post(short_code: str) -> dict:
    """Resolves a post to its CDN video/cover URLs, caption, and top
    comments — one lightweight metadata lookup plus one GraphQL call
    (comments_graphql.fetch_top_comments), no subprocess, no download to
    disk. The app downloads the actual video/cover itself directly from the
    returned CDN URLs (see docs/plan.md for why this replaced the
    CLI-subprocess/zip-archive pivot: that existed only to make bulk
    comment pagination reliable, which the GraphQL top-comments call no
    longer needs).

    Serialized via _lock — resolving is fast (a couple seconds), but still
    only one Instagram-facing call in flight at a time, matching this
    project's standing account-safety principle regardless of how many
    concurrent app requests come in. A randomized breather (see
    _wait_for_breather) is also enforced between posts, not just
    concurrency.

    Logs at request-in, lock-acquired, and finished, specifically so that a
    request the client gives up on and cancels while still queued behind the
    lock (which otherwise would never produce an access-log line at all,
    since uvicorn's own access log only fires once a response is sent)
    still leaves a trace — the "requested" line without a matching
    "finished" line is exactly that signature.
    """
    global _last_call_finished_at

    logger.info("resolve requested short_code=%s", short_code)
    queued_at = time.monotonic()
    with _lock:
        wait = time.monotonic() - queued_at
        logger.info("resolve lock acquired short_code=%s waited=%.1fs", short_code, wait)
        _wait_for_breather()
        try:
            try:
                post = instaloader.Post.from_shortcode(_loader.context, short_code)
            except Exception as e:
                logger.warning("resolve failed short_code=%s error=%s", short_code, e)
                raise ResolveError(f"failed to resolve post: {e}") from e

            if not post.is_video:
                logger.warning("resolve failed short_code=%s error=post has no video", short_code)
                raise ResolveError("post has no video")

            try:
                comments = comments_graphql.fetch_top_comments(
                    _loader.context._session, short_code, str(post.mediaid)
                )
            except comments_graphql.CommentsFetchError as e:
                # Comments are best-effort — a post's video/cover should still
                # be downloadable even if the comments call hiccups.
                logger.warning("resolve comments fetch failed short_code=%s error=%s", short_code, e)
                comments = []

            logger.info("resolve finished short_code=%s", short_code)
            return {
                "short_code": short_code,
                "video_url": post.video_url,
                "cover_url": post.url,
                "caption": post.caption or "",
                "comments": comments,
            }
        finally:
            # Recorded even on failure — a failed attempt still made at
            # least one real Instagram-facing request (from_shortcode), so
            # the next resolve should still wait out a breather relative to
            # it, not treat the failure as if nothing happened.
            _last_call_finished_at = time.monotonic()
