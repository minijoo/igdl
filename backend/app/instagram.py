import asyncio
import logging
import os
import random
import time

import instaloader
from starlette.requests import Request

from . import comments_graphql
from .config import SESSION_USERNAME

logger = logging.getLogger("igdl.resolve")

# One shared, already-authenticated Instaloader instance for the process's
# lifetime rather than re-loading the session file per request — cheap to
# share since every Instagram-facing call goes through _lock below anyway.
_loader = instaloader.Instaloader()
_loader.load_session_from_file(SESSION_USERNAME)
_lock = asyncio.Lock()

# The lock above only ever prevented *concurrent* Instagram-facing calls —
# the instant one resolve released it, the next queued one fired
# immediately, with zero gap. That's a suspiciously regular, zero-jitter
# request pattern regardless of how "slow" any single call is, and is
# suspected of contributing to the account periodically needing
# re-authentication (a real session was replaced via update_session.sh after
# ~100 downloads in an hour triggered this). A randomized pause between
# resolves — not a fixed one, so the spacing itself doesn't become the next
# tell — gives Instagram's traffic a breather between posts even when
# requests are queued back-to-back.
#
# Env-overridable (IGDL_RESOLVE_MIN_GAP_SECONDS / IGDL_RESOLVE_MAX_GAP_SECONDS
# in .env, then `systemctl restart igdl-backend`) rather than hardcoded, so
# this can be dialed way up for a one-time "clear the whole backlog
# overnight, reliability over speed" run (where a human having to relogin
# and reupload the session costs far more time than any amount of extra
# waiting) without a code change/redeploy each time, then dialed back down
# for normal fast day-to-day top-ups.
_MIN_GAP_SECONDS = float(os.environ.get("IGDL_RESOLVE_MIN_GAP_SECONDS", "2.0"))
_MAX_GAP_SECONDS = float(os.environ.get("IGDL_RESOLVE_MAX_GAP_SECONDS", "5.0"))
_last_call_finished_at = 0.0

# A hard ceiling on the *active* Instagram-facing work for one post
# (from_shortcode, or the comments fetch), each timed independently —
# deliberately not a bound on time spent queued behind the lock, which is
# expected to legitimately run into hours for a big overnight batch with a
# wide breather. This guards against a single truly hung call (e.g.
# instaloader's own internal retry/backoff against Instagram taking
# pathologically long) blocking every other resolve behind it indefinitely.
_WORK_TIMEOUT_SECONDS = 180.0


class ResolveError(Exception):
    pass


async def _wait_for_breather() -> None:
    """Sleeps just long enough (if at all) that at least a random
    [_MIN_GAP_SECONDS, _MAX_GAP_SECONDS) interval has passed since the last
    Instagram-facing call actually finished. Must be called while already
    holding _lock — this reads/writes _last_call_finished_at with no
    separate locking of its own. asyncio.sleep, not time.sleep — this holds
    _lock (an asyncio.Lock) across the wait, and blocking the event loop for
    the whole pause would stall every other request on this process, not
    just resolves.
    """
    elapsed = time.monotonic() - _last_call_finished_at
    gap = random.uniform(_MIN_GAP_SECONDS, _MAX_GAP_SECONDS)
    if elapsed < gap:
        pause = gap - elapsed
        logger.info("resolve pausing before Instagram call pause=%.1fs", pause)
        await asyncio.sleep(pause)


async def resolve_post(request: Request, short_code: str) -> dict:
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
    concurrency. The actual instaloader/requests calls are synchronous, so
    they run via asyncio.to_thread — everything else here (the lock, the
    breather, the disconnect checks) is native asyncio so it can actually
    yield instead of blocking the whole process for however long a queued
    request has to wait.

    Checks `request.is_disconnected()` right after acquiring the lock and
    again after the breather — if the client that made this request has
    gone away (e.g. a real network drop, or a background URLSessionTask
    that got cancelled), this skips the actual Instagram-facing work
    instead of burning a rate-limit-relevant request on a response nobody
    will ever receive. This is best-effort, not a guarantee: a force-quit
    doesn't reliably close the underlying connection (confirmed directly —
    a resolve kept running to completion well after the app was killed), so
    a genuinely abandoned request can still occasionally run to completion
    once it reaches the front of the queue. What it does guarantee is that
    this never compounds — the lock is always released after one iteration
    regardless, so a stuck-forever client only ever costs one wasted
    iteration's worth of time for whatever's queued behind it, not more.

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
    async with _lock:
        wait = time.monotonic() - queued_at
        logger.info("resolve lock acquired short_code=%s waited=%.1fs", short_code, wait)

        if await request.is_disconnected():
            logger.info("resolve abandoned short_code=%s (client already disconnected)", short_code)
            raise ResolveError("client disconnected")

        try:
            await _wait_for_breather()

            if await request.is_disconnected():
                logger.info("resolve abandoned short_code=%s (client disconnected during breather)", short_code)
                raise ResolveError("client disconnected")

            try:
                post = await asyncio.wait_for(
                    asyncio.to_thread(instaloader.Post.from_shortcode, _loader.context, short_code),
                    timeout=_WORK_TIMEOUT_SECONDS,
                )
            except asyncio.TimeoutError as e:
                logger.warning("resolve timed out short_code=%s (from_shortcode exceeded %.0fs)", short_code, _WORK_TIMEOUT_SECONDS)
                raise ResolveError("timed out resolving post") from e
            except Exception as e:
                logger.warning("resolve failed short_code=%s error=%s", short_code, e)
                raise ResolveError(f"failed to resolve post: {e}") from e

            if not post.is_video:
                logger.warning("resolve failed short_code=%s error=post has no video", short_code)
                raise ResolveError("post has no video")

            # from_shortcode can itself run for several seconds (longer
            # under instaloader's own retry/backoff) — worth one more
            # check here so a client that disconnected during *that* call
            # at least skips the second Instagram-facing request (comments)
            # instead of paying for both.
            if await request.is_disconnected():
                logger.info("resolve abandoned short_code=%s (client disconnected during from_shortcode)", short_code)
                raise ResolveError("client disconnected")

            try:
                comments = await asyncio.wait_for(
                    asyncio.to_thread(
                        comments_graphql.fetch_top_comments,
                        _loader.context._session, short_code, str(post.mediaid),
                    ),
                    timeout=_WORK_TIMEOUT_SECONDS,
                )
            except asyncio.TimeoutError:
                # Comments are best-effort — a post's video/cover should
                # still be downloadable even if the comments call hangs.
                logger.warning("resolve comments fetch timed out short_code=%s", short_code)
                comments = []
            except comments_graphql.CommentsFetchError as e:
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
