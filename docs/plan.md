# IGDL - Plan

## Summary

A way to download instagram liked and saved videos and watch it on your iPhone, offline. Requires two applications: An iOS app paired with a batch data retriever python script. This means it requires a Mac and an iPhone. 

## Goal

- The Retriever is designed such that a typical Mac user can operate (needing to learn the Terminal being the biggest hurdle). 
- iOS app provides functionality to download the media directly to iPhone, organize what could be thousands of reels, and watch them back through an experience similar to instagram's. Built with safeguards around avoiding unnecessary re-downloads+duplicates+deleted posts, and syncing functionality that effeciently retrieves new videos since last sync.  

## Limitations

1. Retriever will be designed only for LINUX filesystems.
2. Retriever needs to be executed on a Mac/Linux because the program that let's us find the liked and saved posts of an authenticated user requires the bash tool, browser_cookie3, to authenticate the user. 
3. iOS app will be single user to start (not published to App Store).
4. iOS app: SwiftUI + SwiftData, targeting iOS 17+. Development against the Simulator first; physical-device testing comes later. Signed with a personal free Apple ID to start (7-day provisioning — expect to periodically reinstall via Xcode rather than a paid Developer account's longer-lived signing).

## Basic Flow

1. User goes to browser on a Mac and logs into instagram.com
2. User uses Retriever in termianl to start a session using browser cookies from step 1. User runs retrieve. If run for the first time, it may take a while retrieving the post data for all liked and saved posts (video + comments not downloaded in this step).
3. User takes the output of the Retriever script, a Headers file (json), and sends it to their iPhone via AirDrop.
4. User opens IGDL iOS app and imports the newly generated sync file. 
5. IGDL iOS app determines what posts the phone doesn't have and proceeds to download the media for them (video + comments). If run for the first time, this will take a very long time. Wifi is strongly recommended. 
    - BTS: IGDL calls out to our backend server with the shortcode of the video. The backend doesn't require the iOS app/caller to authenticate, but internally it holds its own logged-in instaloader session (a dedicated secondary IG account, not the user's main account) since fetching comments requires a logged-in session even for public posts. See "Backend Download Server" section for the API design. 
6. IGDL iOS app downloads media in the background and saves the video files in the app's sandbox, not in iPhone photos app. 
7. While media is downloading or after downloads finish, User browses IGDL app to watch back offline videos. User can categorize videos into groups. User can delete posts which the app will remember. User can look at storage summary. 

## IGDL iOS App

Building this app can be treated as building a music player app, but for short videos. As such, there is a library of content, there's the ability to categorize each video, like how playlists or albums are maintained, and there's ability go back, go forward and pause. 

- Home Screen mockup
```
-------------------------------
|                             |
|          IGDL      Settings |
|-----------------------------|
|  Recently Added             |
|  ------------------------   |
|  |       |       |      |   |
|  |   1   |   2   |   3  |   |
|  |       |       |      |   |
|  ------------------------   |
|  -----------------          |
|  |       |       |          |
|  |   4   |   5   |          |
|  |       |       |          |
|  -----------------          |
|                             |
|  Playlists                  |
|  -------------------------  |
|  Self-help              >   |
|  -------------------------  |
|  Funny                  >   |
|  -------------------------  |
|                             |
|   ----------------------    |
|   | Home | Lib. | Srch |    |
|   ----------------------    |
-------------------------------
```
- Library Screen Mockup
```
-------------------------------
|                             |
|          IGDL      Settings |
|-----------------------------|
|  Library                    |
|  -------                    |
|  Playlists                  |
|  -------------------------  |
|  Creators                   |
|  -------------------------  |
|  Videos                     |
|  -------------------------  |
|  Categories                 |
|                             |
|                             |
|                             |
|                             |
|                             |
|                             |
|                             |
|                             |
|                             |
|                             |
|   ----------------------    |
|   | Home | Lib. | Srch |    |
|   ----------------------    |
-------------------------------
```
- Playback Screen Mockup (Normal)
```
-------------------------------
|                             |
|                             |
|                             |
|                             |
|                             |
|                             |
|                             |
|                             |
|                             |
|                             |
|         [Play               |
|         Button]             |
|                             |
|         [mute]              |
|                             |
|                             |
|                             |
|                             |
|                      [com.] |
|                             |
|-----------------------------|
| [username] - [date posted]  |
| [caption]                   |
|                             |
|                             |
-------------------------------
```
- Playback Screen Mockup (Expanded)
```
-------------------------------
|       |            |        |
|       |            |        |
|       |            |        |
|       |    video   |        |
|       |            |        |
|       |            |        |
|       |            |        |
|       |            |        |
|-----------------------------|
| [username] - [date posted]  |
| [caption]                   |
|                             |
|                             |
|                             |
|-----------------------------|
| Comments                    |
| [name] [date]               |
| [comment text]              |
| --------------------------- |
| [name] [date]               |
| [comment text]              |
| --------------------------- |
| [name] [date]               |
| ...                         |
-------------------------------
```

- Playback screen 
    - The playback screen is initiated with a playlist and a position in the playlist. When initiated from a category list, the list of videos in that category list is turned into a playlist, and the position of that video in that list is sent to the screen. If initiated from recently added or all videos list, the entire list is turned into a playlist, and then that and the position of the video are sent.  
    - Swiping up on the playback screen will drag the next video on the playlist into view. Releasing snaps the next video into frame and starts playing that video while simultaneously the first video stops. 
    - Swiping down will drag the previous video into view. Same play start/stop behavior applies as above. 


## Saving Videos in the iOS app

- Download Screen Mockup
```
-------------------------------
|                             |
|          IGDL      Settings |
|-----------------------------|
|  < (back)                   |
|  Download                   |
|-----------------------------|
|  (New videos were found)    |
|  Video Info                 |
|  -------------------------  |
|  [x] [username] - [code]    |
|  [caption truncated]        |
|  -------------------------  |
|  [ ] [username] - [code]    |
|  [caption truncated]        |
|  -------------------------  |
|  [x] [username] - [code]    |
|  [caption truncated]        |
|  -------------------------  |
|  [ ] [username] - [code]    |
|  [caption truncated]        |
|  -------------------------  |
|                             |
|                             |
|                             |
|                             |
|                             |
|                             |
|                             |
|      Download Selected      |
|                             |
-------------------------------
```

Given how many liked/saved posts there can be (thousands), downloading everything at once isn't realistic given on-device storage — so the user selects which posts to download from this screen (checkbox per item, "Download Selected" rather than "Download All"). The screen isn't a one-time post-import step: it's revisitable at any time and always shows every item where `fetched = false`, since that state is persisted locally from whatever headers file(s) have been imported so far. The user can download a batch now, close the app, and come back later to download more from the same or a newer import.

The download process calls the backend's `GET /downloads/resolve?short_code=...`, a single synchronous call that returns `video_url`/`cover_url` (Instagram CDN links), `caption`, and the post's top comments (see Backend Download Server) — the app then downloads the video and cover directly from those CDN URLs itself and saves them into the app's sandbox, refreshing `captionText` from the resolved caption since that reflects the current caption, not the headers-file snapshot. This should run asynchronously so that the UI isn't locked for the user. The video should not be saved in the photos app. I am not knowledgable about iOS App storage, and it is something I will research further. But the folder/location should be identified by the short code, and the database record for that video should be updated to indicate the files have been fetched. 

Once a batch is started, those items move out of the selectable list into a separate "Downloading" section — a perpetual, indeterminate spinner per item wasn't informative enough, so video downloads report real progress (a percentage, computed from actual bytes received against the response's content length) rather than just showing that *something* is happening. A permanently failed item stays in the Downloading section with a retry affordance (tap to move it back to the selectable list) rather than blocking there forever with no way out.

Library (Videos/Playlists/Creators/Categories) and Home's Recently Added only show videos where `fetched = true`. Header-only data (no local video file yet) isn't enough for a user to watch or meaningfully organize anything, so surfacing thousands of grayed-out, un-fetched rows there was more distracting than useful — the Download screen is the one place unfetched videos are shown, since that's the screen whose entire purpose is doing something about them.

## Backend Download Server

A Python/FastAPI service, run separately from the Retriever script, whose job is to turn a `short_code` into everything an iOS app needs for one post: video/cover CDN URLs, caption, and top comments. It does not require the iOS app/caller to authenticate — it holds its own logged-in instaloader session internally.

### History: two earlier designs, and why neither stuck

**Design 1 (original):** resolved `video_url`/`cover_url` anonymously and ran only comments through an authenticated Python `get_comments()` call. Fell apart empirically: `get_comments()` routes through instaloader's iPhone-endpoint pagination for any post with more comments than `NodeIterator.page_length()` (12), that endpoint has no real per-page retry, and a single bad page kills the whole fetch with no partial-resume — real-world failure rates were high (roughly half of tested posts on a normal day). Diagnosis found two real mechanisms: (1) a session whose only authenticated action is "go straight for comments on arbitrary posts" reads as a scraper — warming it up by downloading the post's video through the same authenticated context first measurably helped; (2) reliability still didn't fully hold up, and the actual root cause turned out to be the dedicated account having been silently issued a Instagram **`checkpoint_required`** flag — invisible to normal API calls, only surfaced via `instaloader.test_login()`. No code-level fix works around an account-level security checkpoint; only clearing it does.

**Design 2 (CLI-subprocess/zip archive):** once the checkpoint was cleared, pivoted to shelling out to the real `instaloader` CLI (`--comments -l <account> -- -<short_code>`), which downloads video, cover, full comments, and caption together into one archive.zip the app would poll for and download. This was genuinely more reliable than Design 1 — until a post with 2,500+ comments took over 10 minutes to finish (instaloader paginating every single comment, plus a real "too many queries, wait 24 minutes" abuse-detection backoff mid-fetch) and blew past even a generous subprocess timeout. The CLI's `--comments` flow has no concept of "just give me the top N" — it always walks the entire comment list.

**Design 3 (current):** reverse-engineered the GraphQL request Instagram's own web client (`PolarisPostCommentsContainerQuery`) uses to show a post's top comments — the same query that runs when a human opens a post in a browser. One bounded POST to `https://www.instagram.com/api/graphql` returns Instagram's own top-comments curation (~15, in Instagram's own order — no local re-sorting or "top N by likes" logic needed) regardless of whether the post has 5 comments or 5,000. This eliminates the entire reason Design 2's subprocess/zip/job-polling machinery existed — comment pagination was the only thing that ever needed authenticated warm-up or a background job — so the backend reverted to Design 1's shape (backend resolves, app downloads video/cover directly from Instagram's CDN) with Design 3's comments call standing in for the old, unreliable `get_comments()`.

### Reverse-engineering the comments GraphQL call

Captured from Chrome DevTools (Copy as cURL) on a real logged-in session, then rebuilt from scratch in Python since a byte-exact replay of the captured request failed — its `lsd`/`fb_dtsg` auth tokens turned out to be page-load-scoped, not reusable. The working recipe (`backend/app/comments_graphql.py`):

1. `GET https://www.instagram.com/p/{short_code}/` with the account's session cookies, to scrape fresh `lsd`, `fb_dtsg`, and `hsi` tokens out of the page's inline bootstrap JSON. These must be re-scraped on every call — they can't be cached.
2. `jazoest` (an `fb_dtsg` checksum) doesn't need scraping — it's exactly `"2" + sum(ord(c) for c in fb_dtsg)`, confirmed by direct computation.
3. `POST https://www.instagram.com/api/graphql` with `doc_id` (identifies the persisted query server-side, tied to Instagram's web app build — may need updating if Instagram redeploys this component), `variables` (`media_id` + a relay flag), and the tokens above. Critically, this also requires Chrome's full Client Hints header set (`sec-ch-ua*`, `sec-fetch-*`, `priority`, `accept-language`) — without them Instagram's backend returns a generic `"Your Request Couldn't be Processed"` (error 1357054) even with perfectly valid, freshly-scraped tokens; these headers are apparently validated for consistency with the user-agent, not just carried along cosmetically.
4. `media_id` itself comes from a cheap instaloader `Post.from_shortcode` lookup — the same call already used for video/cover resolution, so no extra round-trip.

Validated against two different posts, including the one that originally timed out at 10+ minutes under Design 2 (2,500+ comments) — now resolves in ~6-14s total, same cost as any other post since it's never paginating.

### Endpoint

| Method & path | Purpose |
|---|---|
| `GET /downloads/resolve?short_code=...` | Synchronous — resolves `video_url`, `cover_url`, `caption`, and `comments` (top ~15, Instagram's own order) in one call. |

Example response:
```json
{
    "short_code": "DdSMz4YOGsv",
    "video_url": "https://scontent....mp4",
    "cover_url": "https://scontent....jpg",
    "caption": "...",
    "comments": [
        {"id": 18030397925852411, "text": "...", "owner": "m81sound", "likes_count": 24025, "created_at_utc": "..."}
    ]
}
```

### Design notes

- **No more job queue, job IDs, or on-disk job state.** Resolving is a couple seconds of lightweight metadata + one GraphQL call, not a multi-minute subprocess — synchronous request/response is simpler and there's nothing left to poll for.
- **Still only one Instagram-facing call in flight at a time**, via a `threading.Lock` around the whole resolve — matches the account-safety principle from Designs 1-2, just without the heavier worker-thread/queue machinery a long-running subprocess needed.
- **Comments are best-effort:** if `comments_graphql.fetch_top_comments` raises, `resolve_post` catches it and returns an empty comments list rather than failing the whole resolve — a post's video/cover should still be downloadable even if the comments call hiccups.
- **No more server-side storage at all.** Design 2's `archive.zip`-per-job and its (never-built) purge policy are gone along with the job queue — the backend holds no per-post state between requests.
- **`username` is no longer a request parameter.** It only ever existed to force-include the requesting account's own comments in the pruned top-N; that rule is gone now that "top comments" means whatever Instagram itself curates, unmodified.

### Deployment

Runs on a DigitalOcean droplet (`159.223.135.92`, Ubuntu 24.04, 1 vCPU / 512MB RAM — small enough that a 1GB swapfile was added as a safety margin) rather than staying tied to the Mac. Reachable at `https://igdl.jordys.site`.

- **Process:** a dedicated `igdl` system user (not root, not the personal `jordy` account) runs the app from `/opt/igdl/backend` inside its own venv, managed by a systemd unit (`igdl-backend.service`) — auto-restarts on failure, starts on boot, `uvicorn` bound to `127.0.0.1:8000` only (never exposed directly to the internet).
- **TLS/reverse proxy:** Caddy in front, reverse-proxying `igdl.jordys.site` → `127.0.0.1:8000`. Caddy handles Let's Encrypt certificate provisioning and renewal automatically — no manual cert management.
- **Firewall:** `ufw`, allowing only SSH (22), HTTP (80), and HTTPS (443). Port 8000 is never opened externally; only Caddy is internet-facing.
- **Auth:** a static shared-secret `X-API-Key` header, checked by a FastAPI dependency (`require_api_key` in `main.py`) on every endpoint. Fails closed — if the server's `IGDL_API_KEY` env var isn't set, every request gets a 500 rather than silently running unauthenticated. The key lives in `/opt/igdl/backend/.env` (mode 600, `igdl`-owned) server-side, and as a compiled-in constant in `BackendClient.swift` client-side — appropriate for a personal single-user deployment with no public repo, not something that would fly for a distributed app. The key is sent only to this backend (`resolve(shortCode:)`), never forwarded to Instagram's CDN (`download(url:onProgress:)` deliberately omits it).
- **Instaloader session:** copied over from the Mac's `~/.config/instaloader/session-imjustaswe` rather than logging in fresh from the droplet. Deliberate: a brand-new login from an unfamiliar datacenter IP looks more suspicious to Instagram's abuse detection than continuing to use a session that's already established and trusted — this project has already been burned once by an account-level `checkpoint_required` flag (see History above) and didn't want to risk re-triggering that. Some residual risk either way (the account's *traffic* now originates from the droplet's IP instead of the Mac's), but reusing the session was judged the safer of the two options.
- **Why a domain, not just the raw IP:** iOS's App Transport Security has a built-in exemption for loopback (`127.0.0.1`), which is why the original local setup worked over plain HTTP — but a public IP or domain over HTTP would be blocked by ATS on a real device by default. A domain was needed to get real HTTPS via Let's Encrypt (which doesn't practically issue certs for bare IPs); the ATS problem is what made HTTPS non-optional, not just good practice.

Redeploying after a backend code change: `rsync` the changed files to `/opt/igdl/backend/`, then `ssh root@159.223.135.92 systemctl restart igdl-backend`. No CI/CD pipeline — deploys are manual, matching the project's scale.

## Generating Headers File (Python Script)

The headers file is generated by the user's Mac machine (see why in Limitations section). A script should be written that authenticates an instagram user such that their liked and saved posts can be retrieved, and then retrieves the header info for each of those posts. The generated headers file will represent what that instagram user has liked and saved up to this point. 

## Importing Headers File in the app

Once generated, it is imported into the app from the Sync page, via a manual file picker (SwiftUI `.fileImporter` pointed at Files) rather than a custom file-type "Open In" handoff — the fancier AirDrop-direct-to-app flow is left for a later phase. This process will first store the new headers file in the app's store, then process its contents. It should go through all the items in the headers file and upsert an entry into the app's database. The database should contain the following columns:

Video table:
- pk: string, primary key
- original_width: number
- original_height: number
- video_duration: number (seconds, fractional), optional/nullable — null for photo posts and for anything synced before this field was added. Shown on the Download screen so the user has a general sense of how long a download might take based on video length.
- like_count: number
- caption_text: string
- comment_count: number
- username: string
- user_pk: string
- user_profile_pic_url: string
- short_code: string
- taken_at: number
- sources: list of strings ("liked" and/or "saved") — which feed(s) the item came from. A post can be both (49 of the current ~5,188 are, as of the last merge) — it's a list, not a single value, for exactly that reason. Used only at import time to decide default playlist membership (see Categories & Playlists below): any item with "saved" in `sources` is auto-added to the built-in "Saved" playlist, regardless of whether "liked" is also present.
- category: string, optional/nullable. No default is assigned on import — a video has no category until the user manually assigns one.
- fetched: boolean, true indicates the video and comment file were fetched. 

(Note: fix casing and types to align with Swift code. Also note: `caption_created_at_utc` and `device_timestamp`, mentioned in earlier drafts of this column list, were dropped — `caption_created_at_utc` is redundant with `taken_at` to within a few minutes of jitter, and `device_timestamp` is the uploading device's own unvalidated clock, observed reading a nonsensical future date on real data. `taken_at` (server-assigned, reliable) covers "date posted" on its own.)

The headers file should be a JSON string of general sync data, and a list of items. Each item should map trivially to a row in the Video table. It is called "headers" file because it holds the header data of the videos that need to be downloaded. Built by `build_headers.py`, which merges `liked_snapshot.json` and `saved_snapshot.json` (produced by the Retriever, `main.py`) by `short_code`, unioning `sources` for posts present in both.

Headers file structure:
```json
{
    "retrieved_at": [unix timestamp],
    "authenticated_user_username": [string],
    "items": [
        {
            "pk": [string],
            "short_code": [string],
            "original_width": [number or null — null for anything synced before this field was added],
            "original_height": [number or null],
            "video_duration": [number (seconds) or null — null for photo posts and anything synced before this field was added],
            "like_count": [number],
            "caption_text": [string],
            "comment_count": [number],
            "username": [string],
            "user_pk": [string],
            "user_profile_pic_url": [string, signed/expiring CDN URL — re-resolve at display/download time, don't treat as stable],
            "taken_at": [unix timestamp],
            "sources": [list of "liked" and/or "saved"]
        }
    ]
}
```

### Categories & Playlists

Two separate concepts:
- **Category**: a single optional value per video (the `category` column above), assigned manually by the user. No default assignment on import.
- **Playlist**: a many-to-many relationship between videos and playlists (a video can belong to more than one), separate from the Video table. General playlist curation (user creating/renaming playlists, manually adding/removing videos) is deferred to a later phase. The one piece of playlist behavior needed now: a built-in "Saved" playlist that every item with "saved" in `sources` is automatically added to at import time. Liked-only items get no default playlist.

## iOS App Build Order

1. **Skeleton + data model** — DONE. `ios/IGDL/` (project generated via XcodeGen from `project.yml`, not hand-edited `.xcodeproj`). SwiftData models (`Video`, `Category`, `Playlist`) per the schema above, `HeadersImporter` (upserts by `pk`, bulk-fetches existing rows instead of one query per item — matters at 5,000+ items, applies the "Saved" playlist rule on every upsert so it also catches a video becoming saved on a later sync, not just first import). Home/Library/Search render live SwiftData queries. `SyncView` has the real `.fileImporter` plus a `#if DEBUG`-only shortcut to load a headers file straight from a filesystem path (env-var overridable, used by UI tests) without needing the picker. Covered by `IGDLTests` (importer logic against the real headers.json) and `IGDLUITests` (drives the actual app).
2. **Download pipeline** — DONE (rebuilt again after the backend reverted from its CLI-subprocess/zip-archive design back to CDN-direct resolution — see Backend Download Server's Design 3). `DownloadView`: per-item checkbox selection (not "Download All"), `@Query`'d to `!fetched` so it's naturally revisitable at any time — a row disappears once its video downloads successfully, no separate "already downloaded" bookkeeping needed. Once started, an item moves into a separate "Downloading" section showing per-item state (`resolving` while `GET /downloads/resolve` runs, then real download progress via `URLSession.bytes(for:)` while the video downloads directly from Instagram's CDN); a permanently failed item stays there with a tap-to-retry that moves it back to the selectable list. `BackendClient.resolve(shortCode:)` calls the backend's one synchronous endpoint to get `video_url`/`cover_url`/`caption`/`comments`; `DownloadManager` then downloads video and cover directly from those CDN URLs (no zip, no extraction step), saves video/cover/comments via `MediaStore` (Application Support, keyed by `short_code`, not Photos/Files-app-visible), and refreshes `captionText` from the resolved caption. Runs with bounded concurrency (4 at a time) rather than fully sequential or fully parallel — the backend still only makes one Instagram-facing call at a time internally, but the CDN downloads themselves are fine running in parallel since they never touch Instagram's authenticated API. No longer needs a `username` param anywhere in this flow (see Backend Download Server design notes), and no longer depends on ZIPFoundation.
3. **Playback** — DONE. `PlaybackView`: vertical Reels-style pager (SwiftUI's `.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)`, iOS 17+) over a `[Video]` + start index built by `Array.playableList(startingAt:)` — every list view (Home's Recently Added, Videos, a Playlist, a Creator, a Category) turns itself into a playlist this way via `PlayableVideoRow`. These lists only ever contain `fetched` videos in the first place (see the Download screen note above), so there's nothing undownloaded to skip over at playback time. Only the current page ±1 get a live `AVPlayer` (chromeless, via a `PlayerLayerView` wrapping `AVPlayerLayer` directly rather than SwiftUI's `VideoPlayer`, which shows native controls this UI doesn't want), created/torn down as the current index changes — not one player per video. Tapping the video toggles play/pause; tapping the comments count (now positioned above the caption block rather than beside it, so a multi-line expanded caption never overlaps it) expands the page into the second mockup layout (video shrinks, real comments load from the downloaded `comments.json` below) per `PlaybackPageView`. The caption itself is tap-to-expand/collapse, since many run multiple lines. The close control is a top-left back-chevron positioned at the safe area's top edge (not a guessed padding value) plus a swipe-right-to-dismiss gesture, matching iOS's edge-swipe-back convention; mute is hidden while playing and only appears (above the play icon) when paused, so nothing sits permanently over the video. Re-entering an already-visited page always resumes fresh (not remembering a prior pause or expanded state), matching typical Reels/TikTok behavior. Video rendering uses `.resizeAspect` (never `.resizeAspectFill`), so a video whose aspect ratio doesn't match the screen gets letterboxed/pillarboxed rather than cropped — confirmed against a real wide (1092x718) video and normal Reels-shaped ones. Below the caption tray sits a scrubber: a thin full-width track with a slim vertical-bar thumb (not a round knob) that can be dragged to seek anywhere, backed by a periodic `AVPlayer` time observer (detached/reattached via `.task(id:)` keyed on the player's identity, since `AVPlayer` isn't Equatable) that's suspended while actively dragging so it doesn't fight the gesture. Tap-to-pause is a plain `.onTapGesture` on the video area. Long-press-to-2x was attempted and ultimately **dropped** — the investigation is worth recording in full, since it eliminated an entire category of approach for this specific view:

1. **`.onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)`** (a raw UIKit-backed recognizer, not a `Gesture`-protocol construct) doesn't reliably lose to a descendant's `.highPriorityGesture` — a tap on the caption or a drag on the scrubber was still reaching its `onPressingChanged` and toggling play/pause underneath, even though the descendant's own tap/drag also fired.
2. Rebuilding it as a plain `DragGesture(minimumDistance: 0)` attached via `.gesture()` fixed that, but broke something else entirely: `.gesture()` (like `.onLongPressGesture`) claims exclusive priority over *ancestors* too by default — including `PlaybackView`'s vertical `ScrollView`-based pager one level up. This reliably stole every touch from the pager's own pan gesture before it could start tracking, so swiping up/down to advance between videos stopped working — confirmed by screenshotting a real swipe and seeing the video merely pause (from the gesture's own release handling) rather than the page changing.
3. Switching to `.simultaneousGesture(DragGesture(minimumDistance: 0)...)` — which shouldn't claim exclusivity from ancestors at all — still didn't restore paging when tested directly on-device. Automated XCUITest couldn't distinguish "still broken" from "tooling can't drive this pager" (a pre-existing limitation of this exact `.scrollTargetBehavior(.paging)` setup, unrelated to any of this gesture work), so this needed live, on-device confirmation from the user throughout.
4. The user's own structural test broke the deadlock: dragging inside the comments drawer (plain SwiftUI content, no gesture, no `PlayerLayerView`) paged between videos correctly; dragging the video area never did. The only material difference is `PlayerLayerView` (`UIViewRepresentable` wrapping a raw `AVPlayerLayer`-backed `UIView`) sitting in the video area's hit-testing path. Setting `view.isUserInteractionEnabled = false` there (it has no native controls to interact with anyway — see `PlayerLayerView.swift`) was a reasonable, principled fix but **did not** resolve it — confirmed by the user immediately after.
5. Isolating further: removing *all* gesture code from the video area (down to nothing) still paged fine per the user, and adding back just `.onTapGesture` (a discrete gesture with no continuous/interim reporting at all) also paged fine. Reintroducing 2x via `LongPressGesture(...).updating($state)` — a different `Gesture`-protocol type from `DragGesture`, chosen on the theory that a "did this stay still" check wouldn't compete with the `ScrollView`'s pan tracking the way continuous drag-translation reporting does — broke paging again, confirmed live by the user.

**Conclusion**: the common thread across every failing attempt was continuous touch tracking — anything using `.onChanged`/`.updating`, regardless of underlying gesture type (`DragGesture` or `LongPressGesture`) or priority modifier (`.gesture`, `.onLongPressGesture`, `.simultaneousGesture`) — breaks `PlaybackView`'s `ScrollView(.paging)` when attached to content inside it. Only a genuinely discrete gesture (`TapGesture`/`.onTapGesture`, which reports nothing until a single final recognition) coexists with it. Long-press-to-2x is dropped rather than shipped broken; revisiting it needs an approach that avoids attaching any continuously-tracking gesture to this specific view — e.g., a control overlay positioned *outside* the `ScrollView` entirely (a sibling in `PlaybackView`, tracking the active page via `scrollPosition` and rendered on top), not a descendant of the scrollable content at all. Verified via `testTapPausesWithoutBreakingDismiss` (tap-to-pause + swipe-to-dismiss still coexist) and `testLargeVerticalDragDoesNotPauseVideo` (a large drag never pauses — now trivially true, since a discrete tap gesture doesn't fire for large movement, but kept as a regression guard). Actual swipe-to-advance-the-page behavior isn't covered by an automated test at all — XCUITest's synthetic drags are known to not reliably trigger a real page transition against this specific pager even when the underlying behavior is correct (confirmed directly on-device instead; see `testPlaybackAspectFitAcrossPortraitAndWideVideos`, which works around the same limitation by opening videos directly rather than swiping between them).

The Download screen also shows each pending video's duration (from the headers file's `video_duration`, formatted "M:SS" via `Video.formattedDuration`) beside its row, so the user has a general sense of how long a download might take based on video length; omitted for photo posts or anything synced before this field existed.
4. **Organization** — NEXT. Category assignment UI, playlist curation UI (creating/managing playlists beyond the default "Saved" one). Creators grouping is already done (built alongside Phase 1's Library screen).
5. **Polish** — settings, sync status/progress UX, storage summary, delete-with-memory, failed-download retry.
