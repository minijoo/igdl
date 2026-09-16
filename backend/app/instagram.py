import threading

import instaloader

from . import comments_graphql
from .config import SESSION_USERNAME

# One shared, already-authenticated Instaloader instance for the process's
# lifetime rather than re-loading the session file per request — cheap to
# share since every Instagram-facing call goes through _lock below anyway.
_loader = instaloader.Instaloader()
_loader.load_session_from_file(SESSION_USERNAME)
_lock = threading.Lock()


class ResolveError(Exception):
    pass


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
    concurrent app requests come in.
    """
    with _lock:
        try:
            post = instaloader.Post.from_shortcode(_loader.context, short_code)
        except Exception as e:
            raise ResolveError(f"failed to resolve post: {e}") from e

        if not post.is_video:
            raise ResolveError("post has no video")

        try:
            comments = comments_graphql.fetch_top_comments(
                _loader.context._session, short_code, str(post.mediaid)
            )
        except comments_graphql.CommentsFetchError:
            # Comments are best-effort — a post's video/cover should still
            # be downloadable even if the comments call hiccups.
            comments = []

        return {
            "short_code": short_code,
            "video_url": post.video_url,
            "cover_url": post.url,
            "caption": post.caption or "",
            "comments": comments,
        }
