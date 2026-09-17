import json
import re
import time
from datetime import datetime, timezone

import requests

# Instagram's own web client (codename "Polaris") fetches a post's top
# comments via this persisted GraphQL query rather than the paginated
# private-API comments endpoint instaloader's CLI uses. One request, always
# returns Instagram's own "top comments" curation regardless of how many
# thousands of comments a post has — which is exactly why this replaces the
# CLI's --comments flow (see instagram.py): that flow walks every comment
# page by page and could take 10+ minutes (and trip Instagram's abuse
# detection) on a heavily-commented post; this is one bounded request no
# matter the comment count.
#
# doc_id identifies the persisted query server-side and is tied to
# Instagram's web app build. Reverse-engineered from a real browser session
# on 2026-09-16 — expect this to need updating if Instagram redeploys the
# PolarisPostCommentsContainerQuery component (infrequent, but not never).
DOC_ID = "28319576384320582"

WEB_USER_AGENT = (
    "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/152.0.0.0 Mobile Safari/537.36"
)

# Reverse-engineered from Chrome DevTools: without the full Client Hints
# set below, Instagram's backend rejects the request with a generic
# "Your Request Couldn't be Processed" error even with perfectly valid,
# freshly-scraped auth tokens — these headers apparently get validated for
# consistency with the user-agent, not just carried along for show.
WEB_HEADERS_BASE = {
    "accept": "*/*",
    "accept-language": "en-US,en;q=0.9",
    "content-type": "application/x-www-form-urlencoded",
    "origin": "https://www.instagram.com",
    "priority": "u=1, i",
    "sec-ch-prefers-color-scheme": "dark",
    "sec-ch-ua": '"Chromium";v="152", "Not?A_Brand";v="24", "Google Chrome";v="152"',
    "sec-ch-ua-full-version-list": (
        '"Chromium";v="152.0.7977.84", "Not?A_Brand";v="24.0.0.0", "Google Chrome";v="152.0.7977.84"'
    ),
    "sec-ch-ua-mobile": "?1",
    "sec-ch-ua-model": '"Pixel 9"',
    "sec-ch-ua-platform": '"Android"',
    "sec-ch-ua-platform-version": '"15"',
    "sec-fetch-dest": "empty",
    "sec-fetch-mode": "cors",
    "sec-fetch-site": "same-origin",
    "user-agent": WEB_USER_AGENT,
    "x-asbd-id": "359341",
    "x-fb-friendly-name": "PolarisPostCommentsContainerQuery",
    "x-ig-app-id": "1217981644879628",
    "x-ig-max-touch-points": "1",
}


class CommentsFetchError(Exception):
    pass


def fetch_top_comments(session: requests.Session, short_code: str, media_id: str) -> list[dict]:
    """Returns Instagram's own "top comments" for a post, in the order
    Instagram ranks them — no re-sorting. `session` must already carry the
    account's auth cookies (reuses instaloader's own session so there's a
    single consistent cookie jar across every Instagram-facing call).

    lsd/fb_dtsg/hsi are page-load-scoped tokens (confirmed by testing: a
    byte-exact replay of a real captured request fails once those go
    stale), so every call re-scrapes them from a fresh load of the post
    page first — there's no way to cache and reuse them across calls.

    Every requests-level failure (a raise_for_status() 4xx/5xx — a 429 in
    particular, since this hits Instagram a second/third time per post on
    top of the from_shortcode call — a connection error, a timeout) is
    normalized to CommentsFetchError here. Without this, a raw
    requests.exceptions.RequestException would propagate past
    instagram.py's `except comments_graphql.CommentsFetchError` (it only
    matches that one type), defeating the "comments are best-effort" intent
    entirely: a transient comments-only failure would kill the whole
    resolve, including the video/cover URLs that had already resolved fine.
    """
    try:
        return _fetch_top_comments(session, short_code, media_id)
    except requests.exceptions.RequestException as e:
        raise CommentsFetchError(f"request failed: {e}") from e


def _fetch_top_comments(session: requests.Session, short_code: str, media_id: str) -> list[dict]:
    page_url = f"https://www.instagram.com/p/{short_code}/"
    page = session.get(page_url, headers={"user-agent": WEB_USER_AGENT}, timeout=15)
    page.raise_for_status()

    lsd = _extract(page.text, r'"LSD"\s*,\s*\[\]\s*,\s*\{\s*"token"\s*:\s*"([^"]+)"', "lsd")
    fb_dtsg = _extract(page.text, r'"DTSGInitData"\s*,\s*\[\]\s*,\s*\{\s*"token"\s*:\s*"([^"]+)"', "fb_dtsg")
    hsi = _extract(page.text, r'"hsi"\s*:\s*"(\d+)"', "hsi")
    jazoest = "2" + str(sum(ord(c) for c in fb_dtsg))
    csrftoken = session.cookies.get("csrftoken", domain=".instagram.com") or ""

    headers = dict(WEB_HEADERS_BASE)
    headers.update({
        "referer": f"https://www.instagram.com/p/{short_code}",
        "x-csrftoken": csrftoken,
        "x-fb-lsd": lsd,
    })

    variables = json.dumps({
        "media_id": media_id,
        "__relay_internal__pv__PolarisIsLoggedInrelayprovider": True,
    })
    data = {
        "av": "17841423990016929",
        "__d": "www",
        "__user": "0",
        "__a": "1",
        "__req": "m",
        "__ccg": "EXCELLENT",
        "dpr": "3",
        "__comet_req": "7",
        "__hsi": hsi,
        "__spin_r": "1047671450",
        "__spin_b": "trunk",
        "__spin_t": str(int(time.time())),
        "__crn": "comet.igweb.PolarisPostRouteNext",
        "fb_dtsg": fb_dtsg,
        "jazoest": jazoest,
        "lsd": lsd,
        "fb_api_caller_class": "RelayModern",
        "fb_api_req_friendly_name": "PolarisPostCommentsContainerQuery",
        "server_timestamps": "true",
        "variables": variables,
        "doc_id": DOC_ID,
    }

    resp = session.post("https://www.instagram.com/api/graphql", headers=headers, data=data, timeout=15)
    resp.raise_for_status()
    text = resp.text.removeprefix("for (;;);")
    try:
        body = json.loads(text)
    except json.JSONDecodeError as e:
        raise CommentsFetchError(f"non-JSON response: {text[:300]}") from e

    if body.get("error") or "errors" in body:
        raise CommentsFetchError(f"graphql error: {json.dumps(body)[:500]}")

    edges = (
        body.get("data", {})
        .get("xdt_api__v1__media__media_id__comments__connection", {})
        .get("edges", [])
    )
    return [_to_comment(e["node"]) for e in edges]


def _to_comment(node: dict) -> dict:
    return {
        "id": int(node["pk"]),
        "text": node.get("text") or "",
        "owner": node["user"]["username"],
        "likes_count": node.get("comment_like_count", 0),
        "created_at_utc": datetime.fromtimestamp(node["created_at"], tz=timezone.utc).isoformat(),
    }


def _extract(text: str, pattern: str, name: str) -> str:
    match = re.search(pattern, text)
    if not match:
        raise CommentsFetchError(f"could not find {name} token on post page")
    return match.group(1)
