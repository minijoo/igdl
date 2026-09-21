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

Download is its own tab (`RootTabView`: Home, Library, Downloads, Search) rather than a NavigationLink pushed from Home. Two reasons: (1) it needed to be reachable without going through Home first, and (2) a pushed view is popped (and its `@State`, including the in-flight `DownloadManager` tracking per-item progress, torn down) the moment you navigate away — so switching away mid-download and back made the whole "Downloading" section silently vanish even though the real download kept running in the background. SwiftUI keeps every tab's root view (and its `@State`) alive for the life of the `TabView` regardless of which tab is currently selected, so making Downloads a tab root fixed this as a side effect — confirmed via `testDownloadProgressPersistsAcrossTabSwitch`, which switches to Home and back mid-download and asserts the "Downloading" section is still there. The Downloads screen also now distinguishes "nothing imported yet" (`allVideos.isEmpty` — points the user at Settings to import a headers file) from "everything imported is already downloaded" (`pendingVideos.isEmpty` — the existing "Nothing to download" state), since those used to show the same message.

### Downloads survive the app being backgrounded

Originally, the video/cover CDN transfers ran on a plain foreground `URLSession` inside a Swift `Task` owned by `DownloadManager`. That's tied to this process: iOS suspends a backgrounded app within moments, killing the in-flight task mid-transfer, so a user who switched away from the app (not even force-quitting it) mid-batch would come back to see downloads marked failed even though nothing was actually wrong.

Fixed by moving the actual file transfers to `BackgroundDownloadCoordinator`, a singleton wrapping a background `URLSessionConfiguration` (`isDiscretionary = false`, `sessionSendsLaunchEvents = true`). Background sessions hand transfers off to a system daemon (nsurlsessiond) that keeps working independently of this process, including across the process being suspended or terminated by the OS — a user-initiated force-quit still cancels everything, but that's a much narrower case than "the user switched apps." Notable pieces:

- Only supports delegate-based `URLSessionDownloadTask`, not the `async/await session.bytes(for:)` streaming call the old foreground implementation used for live progress — progress now comes from the `urlSession(_:downloadTask:didWriteData:...)` delegate callback instead. `BackendClient.download(url:onProgress:)` was removed entirely since nothing calls it anymore. (`resolve(shortCode:)` was still a plain foreground request at this point — that assumption didn't hold up; see "Resolve also moved to the background session" below.)
- The coordinator has to be a singleton reachable before any SwiftUI view exists, not per-screen `@State` — iOS can relaunch the app in the background purely to deliver a finished transfer, via `AppDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:)` (the one piece SwiftUI has no native equivalent for, hence `@UIApplicationDelegateAdaptor` in `IGDLApp`). It holds a direct reference to the app's shared `ModelContainer` (now created explicitly in `IGDLApp.init()` rather than via the `.modelContainer(for:)` scene modifier, so it can be handed to the coordinator) so it can flip `fetched`/`downloadedAt` from a delegate callback with no view hierarchy around.
- Each `URLSessionDownloadTask`'s `taskDescription` is set to `"<shortCode>|video"` / `"<shortCode>|cover"` — `taskDescription` is OS-preserved metadata that survives the task being reconnected after a process relaunch, so there's no need for a separate persisted task-identifier-to-shortCode mapping.
- A pair is only marked `fetched = true` once both files actually exist on disk (`MediaStore.hasVideo`/`hasCover`), checked from `didCompleteWithError` — this doubles as the "did this whole thing finish" signal across a process relaunch, without needing any additional persisted state.
- `DownloadManager.reconcile()` (called from `DownloadView`'s `.task`) recovers in-progress downloads from the background session's own task list on (re)appearance — necessary because a fresh `DownloadManager`/`BackgroundDownloadCoordinator` instance (e.g. after the app was actually relaunched) has no in-memory record of what was running, even though the underlying transfers and their progress are still there for the asking (`URLSessionTask.countOfBytesReceived`/`countOfBytesExpectedToReceive`).
- Deliberately doesn't persist failure state across a process relaunch — if the app was fully killed and relaunched, a genuinely failed download just reappears in the plain selectable list, identical to what `resetState`/retry already does. Simpler than maintaining a separate durable failure ledger for a difference the user wouldn't notice.

Verified via `testDownloadCompletesAfterBackgrounding`, which starts a real download, presses the home button (a real process suspension, unlike switching SwiftUI tabs), waits 20s — well past how long the old foreground task would have survived — then reactivates and confirms the download actually completed rather than showing failed.

### Resolve also moved to the background session

The assumption above — "resolve is quick, losing it mid-backgrounding is a cheap one-tap retry" — held until the backend started deliberately pacing resolves tens of seconds to minutes apart (see "A randomized breather" below), at which point a real overnight batch simply stopped with no errors the moment the phone went to sleep. Root cause: `resolve()` and the loop deciding "now resolve the next video" were still plain foreground/in-process work — iOS suspends the whole app process shortly after backgrounding, freezing that loop entirely (not an error, just frozen mid-`await`) — while the video/cover transfers kept going since those were already on the background session. There's no Info.plist flag or entitlement for "let a regular app run indefinitely in the background"; that's reserved for specific capabilities (VoIP, audio, location) that don't apply here, so the only real fix was extending the same background-session pattern to resolve too.

- `BackgroundDownloadCoordinator` gained a `.resolve` `URLSessionDownloadTask` kind — a GET to `/downloads/resolve` with the `X-API-Key` header, same background session as video/cover, tagged `"<shortCode>|resolve"`. Its "downloaded file" is the JSON response body; `didFinishDownloadingTo` reads it as `Data`, decodes it, and (on success) immediately starts the video/cover tasks itself, chaining the whole per-video pipeline together as pure delegate callbacks with no live loop anywhere in it.
- `DownloadManager.downloadSelected` lost its chunking/`maxConcurrent`/`withTaskGroup` machinery entirely — it just calls `coordinator.enqueueResolveAndDownload(shortCode:...)` for every selected video immediately and returns. There's nothing left for the client to throttle: the backend's own lock + breather (see below) paces the real Instagram-facing work regardless of how many requests arrive at once, and a background task tolerates sitting queued far longer than a foreground request's timeout ever could. Confirmed directly against production: selecting 2 videos now shows both `resolve requested` lines land within 1ms of each other in the backend log, instead of one only being sent after the other's foreground request returned.
- `BackendClient` shrank to just `baseURL`/`apiKey` constants — no method, no injectable `URLSession`, since nothing calls it as a client anymore.
- The SwiftData-mutating side of a resolve result (save caption/comments, flip `Video.isVideo` to `false` for "post has no video") moved out of `DownloadManager` into standalone functions in `ResolveHandling.swift`, taking an explicit `ModelContext` — needed since this logic now runs from `BackgroundDownloadCoordinator`'s delegate callback (which can fire with no `DownloadManager`, or even no view hierarchy, around), and as a side benefit it's directly unit-testable (`ResolveHandlingTests`) without simulating a real background transfer, which isn't realistically mockable (background transfers run in a separate system process, not this one — the previous `MockURLProtocol`-based tests for this had to be retired for exactly that reason).
- Verification here relied on live backend log inspection across several runs rather than a clean green end-to-end UI test run — repeated testing against the same 2 fixed real Instagram posts over several days pushed the test account into Instagram's own rate limiting (`Post.from_shortcode` itself started returning "Please wait a few minutes before you try again"), unrelated to this change. The logs directly confirmed the new behavior regardless (simultaneous dispatch, correct lock queueing, correct chaining into video/cover, graceful comments-429 degradation from the fix below all firing together correctly on the same real requests).

### A randomized breather, not just a lock (Instagram abuse-detection avoidance)

A real-world report: with the resolve lock alone, ~100 downloads in an hour preceded the account needing to be re-authenticated (a fresh session uploaded via `backend/update_session.sh`). Theory: the lock only ever prevented *concurrent* Instagram-facing calls — the instant one resolve released it, the next queued one fired immediately, a suspiciously regular, zero-jitter request pattern regardless of how many were queued, independent of raw volume.

`instagram.py`'s `_wait_for_breather()` now sleeps a random `[IGDL_RESOLVE_MIN_GAP_SECONDS, IGDL_RESOLVE_MAX_GAP_SECONDS)` interval (env-configurable in `.env`, defaulting to 2.0/5.0, restart the service to pick up a change — no code edit needed) before each resolve's actual Instagram-facing work, timed from when the *previous* resolve's Instagram traffic finished, recorded even on failure since a failed attempt still made a real request. Randomized rather than fixed so the spacing itself doesn't become a new tell. For a one-time "clear the whole backlog overnight, reliability over speed" run, this can be dialed way up (tens to ~90s) since a human having to relogin/reupload the session costs far more time than any amount of extra waiting — logged at `resolve pausing before Instagram call pause=X.Xs`.

Also fixed while investigating: `comments_graphql.fetch_top_comments`'s `raise_for_status()` calls raised a raw `requests.exceptions.HTTPError`, not the module's own `CommentsFetchError` — so a transient failure on the comments step alone (a 429, observed live) propagated past `instagram.py`'s `except comments_graphql.CommentsFetchError`, killing the entire resolve (video/cover URLs included) instead of falling back to an empty comments list as the "best-effort" comment in the code already claimed. Now wraps the whole call and normalizes any `requests.exceptions.RequestException` to `CommentsFetchError`.

Separately: Ubuntu's daily unattended security-upgrade job (`apt-daily-upgrade` + `needrestart`, ~06:00 UTC + randomized delay) can auto-restart `igdl-backend` if a loaded shared library (e.g. `libssl`) gets patched — observed live, mid-batch. This is graceful (SIGTERM, uvicorn finishes the in-flight request before exiting, back up in ~2s, confirmed no work lost) but worth knowing about since any overnight batch spanning that window has a real chance of hitting it.

### An abandoned client can still clog the resolve queue

A real report: force-quitting the app (not just backgrounding it) doesn't stop the backend from continuing to work through that batch's queued resolves — confirmed live, watching the backend log keep processing requests well after the app was killed. Root cause: the actual network connection for a background `URLSessionTask` is owned by `nsurlsessiond`, a system daemon independent of the app's process — killing the app doesn't necessarily close it, and Apple's classic "force-quit cancels background transfers" guidance doesn't hold up reliably here, at least not for a request that's just idly waiting on a slow response rather than actively streaming bytes. Each such request still burns a full lock turn (breather + a real Instagram-facing call) for a response nobody will ever read, needlessly delaying whatever's queued behind it.

`resolve_post` is now `async def` (the lock is `asyncio.Lock`, the breather is `asyncio.sleep`, and the actual blocking `instaloader`/`requests` calls run via `asyncio.to_thread` so they don't block the event loop) specifically so it can call `await request.is_disconnected()` at three points — right after acquiring the lock, again after the breather, and again after `from_shortcode` (which can itself run for several seconds, longer under instaloader's own retry/backoff) — bailing out before the next Instagram-facing call if the client's already gone.

This is deliberately **best-effort, not a guarantee** — confirmed directly (see `test_instagram.py` and manual local testing with a real dropped `curl` connection) that `is_disconnected()` does work correctly *when* the underlying connection actually closes, but there's no way to confirm from here whether `nsurlsessiond` reliably closes it specifically in the force-quit case. What it does guarantee, independent of whether disconnection is ever detected: the lock is always released after one iteration regardless, so a client that's genuinely unreachable forever only ever costs *one* wasted turn for whatever's behind it, never a growing pileup. On top of that, `_WORK_TIMEOUT_SECONDS` (180s) bounds each individual Instagram-facing call — not a bound on time spent *queued*, which is expected to legitimately run into hours for a wide overnight breather, but a hard ceiling on the *active* work once a request reaches the front, guarding against a single truly hung call (e.g. a pathological instaloader retry loop) blocking everything behind it.

Covered by `backend/app/test_instagram.py` (`unittest.IsolatedAsyncioTestCase`, no real network — `instaloader.Post.from_shortcode`/`comments_graphql.fetch_top_comments` mocked): each of the three disconnect checkpoints, that the lock genuinely serializes concurrent resolves, and the existing no-video/comments-degradation behavior. Run with `.venv/bin/python3 -m unittest app.test_instagram -v` from `backend/`.

Client-side complement: a **"Cancel All Downloads"** button (red text) at the end of the "Downloading" section — `BackgroundDownloadCoordinator.cancelAllTasks()` clears the progress/completion handlers *before* cancelling every in-flight resolve/video/cover task, specifically so cancellation doesn't flow through the normal `failed(...)` path and show up as a per-item "Failed — Cancelled" needing an individual retry; `DownloadManager.cancelAll()` just wipes `states` directly, so everything returns to "Ready for Download" in one shot. This only helps for a batch abandoned *before* quitting — it can't do anything for a force-quit that already happened, which is exactly why the backend-side fix above exists as the real safety net. Verified via `testCancelAllDownloadsReturnsVideosToReadyForDownload`.

### Wi-Fi-only by default (cellular opt-in)

A Settings toggle ("Allow Cellular Data", off by default) controls whether the whole pipeline — resolve *and* video/cover — is allowed to run over cellular. Implemented as `URLRequest.allowsCellularAccess`, set per-request in `BackgroundDownloadCoordinator.startResolve`/`start(url:...)`, not baked into the shared session's `URLSessionConfiguration` — a session's own config is fixed for its lifetime, but reading the preference fresh (`UserDefaults.standard.bool(forKey:)`, defaulting to `false`/off when unset) for every new request means flipping the setting takes effect immediately for whatever's enqueued next, no session recreation needed. `SyncView`'s `@AppStorage` binds the same UserDefaults key directly, so the two stay in sync with no extra plumbing.

When Wi-Fi-only is on and only cellular is available, a background session task doesn't fail — it's held pending until a suitable network shows up, then resumes automatically. `BackgroundDownloadCoordinator` surfaces this via `URLSessionTaskDelegate.urlSession(_:taskIsWaitingForConnectivity:)`, a new `DownloadItemState.waitingForWiFi` case, and a "Waiting for Wi-Fi…" row in `DownloadView` — without it, a download stuck behind this setting would just look frozen with no explanation.

Gotcha hit while testing: a `Toggle` inside a `Form` exposes two nested `Switch` accessibility elements — an outer, row-spanning one (label + control together, for VoiceOver, which is what an `.accessibilityIdentifier` on the `Toggle` resolves to) wrapping the actual small interactive switch at the row's right edge. `XCUIElement.tap()` on the outer element taps its center, which misses the real control entirely — the fix (see `testAllowCellularDownloadsDefaultsOffAndPersists`) is tapping a coordinate near the row's right edge instead of the identified element directly.

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
- **A randomized breather between resolves, not just concurrency.** The lock alone only ever prevented *concurrent* calls — the instant one resolve released it, the next queued one fired immediately, a zero-gap back-to-back pattern regardless of how many were queued. Suspected (not fully confirmed) of contributing to the account periodically needing re-authentication: ~100 downloads in an hour preceded one such incident, and a fresh session (`update_session.sh`) was needed. `_wait_for_breather()` now sleeps a random `[2.0, 5.0)` seconds (not fixed, so the spacing itself doesn't become a new tell) before each resolve's actual Instagram-facing work, timed from when the *previous* resolve's Instagram traffic finished — recorded even on failure, since a failed attempt still made a real request. Confirmed deployed and firing correctly (`resolve pausing before Instagram call pause=X.Xs` in the logs), but a live test immediately hit Instagram's own `"Please wait a few minutes before you try again"` 401 — the account was already in a rate-limit cooldown from the day's volume by the time this shipped, so it hasn't yet been validated against a real batch under normal conditions. Tune `_MIN_GAP_SECONDS`/`_MAX_GAP_SECONDS` in `instagram.py` if batches still trigger this, or loosen them if a batch ends up taking implausibly long.
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
- downloadedAt: date, optional/nullable — set the moment `fetched` becomes true (real download or the DEBUG fixture-seeding path), nil until then. Distinct from `taken_at` (when the post was originally made): Home's "Recently Added" sorts by this descending ("what did I just get"), while Library's "Videos" list keeps sorting by `taken_at` descending ("what did I originally post/like, in order") — two different, both legitimate, orderings of the same underlying data. 

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
2. **Download pipeline** — DONE (rebuilt again after the backend reverted from its CLI-subprocess/zip-archive design back to CDN-direct resolution — see Backend Download Server's Design 3). `DownloadView`: per-item checkbox selection (not "Download All"), `@Query`'d to `!fetched` so it's naturally revisitable at any time — a row disappears once its video downloads successfully, no separate "already downloaded" bookkeeping needed. Once started, an item moves into a separate "Downloading" section showing per-item state (`resolving` while `GET /downloads/resolve` runs, then real download progress via `URLSession.bytes(for:)` while the video downloads directly from Instagram's CDN); a permanently failed item stays there with a tap-to-retry that moves it back to the selectable list. `BackendClient.resolve(shortCode:)` calls the backend's one synchronous endpoint to get `video_url`/`cover_url`/`caption`/`comments`; `DownloadManager` then downloads video and cover directly from those CDN URLs (no zip, no extraction step), saves video/cover/comments via `MediaStore` (Application Support, keyed by `short_code`, not Photos/Files-app-visible), and refreshes `captionText` from the resolved caption. Runs with bounded concurrency (4 at a time) rather than fully sequential or fully parallel — the backend still only makes one Instagram-facing call at a time internally, but the CDN downloads themselves are fine running in parallel since they never touch Instagram's authenticated API. No longer needs a `username` param anywhere in this flow (see Backend Download Server design notes), and no longer depends on ZIPFoundation. A top-right toolbar **"Select…" menu** offers "20 from top" and "20 random" as faster alternatives to hand-checking boxes — 20 was picked as roughly 20-30 minutes of typical Reels-length content, a reasonable single batch for a user's entertainment needs without forcing them to pick from a list that can run into the thousands. Both options are additive and idempotent-safe: `selectFromTop`/`selectRandom` filter to `selectableVideos` not already in `selected` first, then take up to 20 from that filtered set (`.prefix(20)` for top, `.shuffled().prefix(20)` for random) — so pressing either again always adds *more* (from whatever's left) rather than re-selecting or double-counting, and mixing the two (e.g. "20 from top" then "20 random") composes correctly for the same reason. A running "`N` selected" count sits next to the existing bottom "Download Selected (`N`)" button — as a plain row inside the `List`'s own content, not `.safeAreaInset(edge: .top)`: that overlapped the navigation bar's large-title text instead of sitting below it (large titles occupy space that `safeAreaInset` doesn't account for the way it does for a plain nav bar). Verified via `testSelectMenuAddsWithoutDuplicating`.
3. **Playback** — DONE. `PlaybackView`: vertical Reels-style pager (SwiftUI's `.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)`, iOS 17+) over a `[Video]` + start index built by `Array.playableList(startingAt:)` — every list view (Home's Recently Added, Videos, a Playlist, a Creator, a Category) turns itself into a playlist this way via `PlayableVideoRow`. These lists only ever contain `fetched` videos in the first place (see the Download screen note above), so there's nothing undownloaded to skip over at playback time. Only the current page ±1 get a live `AVPlayer` (chromeless, via a `PlayerLayerView` wrapping `AVPlayerLayer` directly rather than SwiftUI's `VideoPlayer`, which shows native controls this UI doesn't want), created/torn down as the current index changes — not one player per video. Tapping the video toggles play/pause; tapping the comments count (now positioned above the caption block rather than beside it, so a multi-line expanded caption never overlaps it) expands the page into the second mockup layout (video shrinks, real comments load from the downloaded `comments.json` below) per `PlaybackPageView`. The caption itself is tap-to-expand/collapse, since many run multiple lines. The close control is a top-left back-chevron positioned at the safe area's top edge (not a guessed padding value) plus a swipe-right-to-dismiss gesture, matching iOS's edge-swipe-back convention; mute is hidden while playing and only appears (above the play icon) when paused, so nothing sits permanently over the video. Re-entering an already-visited page always resumes fresh (not remembering a prior pause or expanded state), matching typical Reels/TikTok behavior. Video rendering uses `.resizeAspect` (never `.resizeAspectFill`), so a video whose aspect ratio doesn't match the screen gets letterboxed/pillarboxed rather than cropped — confirmed against a real wide (1092x718) video and normal Reels-shaped ones. Below the caption tray sits a scrubber: a thin full-width track with a slim vertical-bar thumb (not a round knob) that can be dragged to seek anywhere, backed by a periodic `AVPlayer` time observer (detached/reattached via `.task(id:)` keyed on the player's identity, since `AVPlayer` isn't Equatable) that's suspended while actively dragging so it doesn't fight the gesture. Tap-to-pause is a plain `.onTapGesture` on the video area. Long-press-to-2x was attempted and ultimately **dropped** — the investigation is worth recording in full, since it eliminated an entire category of approach for this specific view:

1. **`.onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)`** (a raw UIKit-backed recognizer, not a `Gesture`-protocol construct) doesn't reliably lose to a descendant's `.highPriorityGesture` — a tap on the caption or a drag on the scrubber was still reaching its `onPressingChanged` and toggling play/pause underneath, even though the descendant's own tap/drag also fired.
2. Rebuilding it as a plain `DragGesture(minimumDistance: 0)` attached via `.gesture()` fixed that, but broke something else entirely: `.gesture()` (like `.onLongPressGesture`) claims exclusive priority over *ancestors* too by default — including `PlaybackView`'s vertical `ScrollView`-based pager one level up. This reliably stole every touch from the pager's own pan gesture before it could start tracking, so swiping up/down to advance between videos stopped working — confirmed by screenshotting a real swipe and seeing the video merely pause (from the gesture's own release handling) rather than the page changing.
3. Switching to `.simultaneousGesture(DragGesture(minimumDistance: 0)...)` — which shouldn't claim exclusivity from ancestors at all — still didn't restore paging when tested directly on-device. Automated XCUITest couldn't distinguish "still broken" from "tooling can't drive this pager" (a pre-existing limitation of this exact `.scrollTargetBehavior(.paging)` setup, unrelated to any of this gesture work), so this needed live, on-device confirmation from the user throughout.
4. The user's own structural test broke the deadlock: dragging inside the comments drawer (plain SwiftUI content, no gesture, no `PlayerLayerView`) paged between videos correctly; dragging the video area never did. The only material difference is `PlayerLayerView` (`UIViewRepresentable` wrapping a raw `AVPlayerLayer`-backed `UIView`) sitting in the video area's hit-testing path. Setting `view.isUserInteractionEnabled = false` there (it has no native controls to interact with anyway — see `PlayerLayerView.swift`) was a reasonable, principled fix but **did not** resolve it — confirmed by the user immediately after.
5. Isolating further: removing *all* gesture code from the video area (down to nothing) still paged fine per the user, and adding back just `.onTapGesture` (a discrete gesture with no continuous/interim reporting at all) also paged fine. Reintroducing 2x via `LongPressGesture(...).updating($state)` — a different `Gesture`-protocol type from `DragGesture`, chosen on the theory that a "did this stay still" check wouldn't compete with the `ScrollView`'s pan tracking the way continuous drag-translation reporting does — broke paging again, confirmed live by the user.

**Conclusion**: the common thread across every failing attempt was continuous touch tracking — anything using `.onChanged`/`.updating`, regardless of underlying gesture type (`DragGesture` or `LongPressGesture`) or priority modifier (`.gesture`, `.onLongPressGesture`, `.simultaneousGesture`) — breaks `PlaybackView`'s `ScrollView(.paging)` when attached to content inside it. Only a genuinely discrete gesture (`TapGesture`/`.onTapGesture`, which reports nothing until a single final recognition) coexists with it. Long-press-to-2x is dropped rather than shipped broken; revisiting it needs an approach that avoids attaching any continuously-tracking gesture to this specific view — e.g., a control overlay positioned *outside* the `ScrollView` entirely (a sibling in `PlaybackView`, tracking the active page via `scrollPosition` and rendered on top), not a descendant of the scrollable content at all. Verified via `testTapPausesWithoutBreakingDismiss` (tap-to-pause + swipe-to-dismiss still coexist) and `testLargeVerticalDragDoesNotPauseVideo` (a large drag never pauses — now trivially true, since a discrete tap gesture doesn't fire for large movement, but kept as a regression guard). Actual swipe-to-advance-the-page behavior isn't covered by an automated test at all — XCUITest's synthetic drags are known to not reliably trigger a real page transition against this specific pager even when the underlying behavior is correct (confirmed directly on-device instead; see `testPlaybackAspectFitAcrossPortraitAndWideVideos`, which works around the same limitation by opening videos directly rather than swiping between them).

The Download screen also shows each pending video's duration (from the headers file's `video_duration`, formatted "M:SS" via `Video.formattedDuration`) beside its row, so the user has a general sense of how long a download might take based on video length; omitted for photo posts or anything synced before this field existed.

Audio plays even with the phone's hardware silent switch on, matching Reels/TikTok/every other short-video app — `AVAudioSession.sharedInstance().setCategory(.playback)` is set once at app launch (`IGDLApp.init`). The default session category respects the silent switch, which isn't what a video-playback app's users expect; `.playback` overrides it while still respecting Do Not Disturb/system volume, and the in-app mute button still works independently on top of it.

The scrubber's touchable track sits 32pt tall regardless of device, with `bottomSafeArea` (the device's actual bottom safe-area inset, read from the page's outer `GeometryReader` and threaded down through `videoArea`) added as plain black space *below* it rather than as padding inside the scrubber's own `GeometryReader` — it previously sat flush against the true bottom edge (since `PlaybackView`'s `ScrollView` uses `.ignoresSafeArea()`), overlapping the home indicator's own swipe-up gesture zone and stealing touches meant for it. Only added when not showing comments — once the comments drawer is up, the video area (and its scrubber) no longer reaches the bottom edge, so there's nothing to clear. The safe-area inset alone still wasn't enough visual separation in practice, so there's a further fixed 20pt on top of it. The pager's `ScrollView` also hides its scroll indicator (`.scrollIndicators(.hidden)`) — a vertical scrollbar has no use here (there's no way to see "how far" through a stream of Reels-style videos you are) and was otherwise visible over the video.
4. **Organization** — PARTIAL. Category assignment — DONE. Playlist curation UI (creating/managing playlists beyond the default "Saved" one) — still NEXT. Creators grouping is already done (built alongside Phase 1's Library screen).

    **Bug found and fixed**: tapping a creator in `CreatorsListView` to push `CreatorDetailView` froze the app — reproduced directly with a UI test (`testCreatorsListDiagnostic`), which showed a genuine ~75s+ main-thread hang ("App event loop idle notification not received"), not a XCUITest timing flake. Bisected by first swapping `CreatorDetailView`'s `PlayableVideoRow` for a plain `Text` row (hang persisted identically — ruled out `PlayableVideoRow`/`PlaybackCoordinator` entirely) then removing `CreatorDetailView`'s own `@Query`. Root cause: `CreatorDetailView` ran an independent `@Query(filter: #Predicate<Video> { $0.fetched })` — the *exact same predicate* as its parent `CreatorsListView`'s own `@Query` — while both were simultaneously alive in the same `NavigationStack` (parent pushing a child with an identical live query). Fix: `CreatorDetailView` no longer queries at all — it takes `allVideos: [Video]` as a plain parameter, passed down from the parent's already-fetched result. Verified via `testCreatorsListDiagnostic` (now completes in ~2s instead of hanging).

    Categorizing (deliberately separate from playlists — a video has at most one category, vs. many playlists) is done entirely from two places: assigning/creating a category happens only from the playback screen's tray; removing a video from a category happens only from the Library's Categories view. Nothing else ever touches the category list — importing/downloading never creates, assigns, or renames categories.

    - **Playback screen**: a new icon-only "tag" button sits directly above the existing comments button in the same trailing icon stack (`bottomInfoBar` in `PlaybackPageView`), opening `CategoryTrayView` as a `.sheet` with `.presentationDetents([.medium, .large])`. The tray lists every `Category`, sorted by `lastUsedAt` descending — most-recently-used at the top, so repeatedly categorizing videos in one sitting doesn't require scrolling through an alphabetical list every time — with a fixed "None" row always last regardless of recency (it isn't a real `Category`, just "clear the assignment"). Tapping any row immediately assigns it to the video, bumps that category's `lastUsedAt`, and dismisses the tray. A "+" button pinned bottom-left (via `.safeAreaInset(edge: .bottom)` with a `Spacer()` after it, not a system toolbar item — bottom-bar toolbar items don't reliably left-align) opens a `.alert` with a `TextField` to create a new category by name; creating one selects it immediately and closes the tray, same as picking an existing one. Name collisions reuse the existing category (by exact trimmed-name match) rather than attempting a duplicate insert against `Category.name`'s unique constraint.
    - **Category model**: `lastUsedAt: Date` (declared with an inline default, not just an initializer default, so SwiftData's lightweight migration can backfill existing rows). No separate stored video-count field — `category.videos.count` via the existing relationship is always correct by construction and can't drift the way a manually-maintained counter could, which matters directly for the next point:
    - **Library's Categories view** (`CategoriesListView`/`CategoryDetailView`): unchanged sort (alphabetical) and unchanged as a pure browse/count view — no assignment happens here. `CategoryDetailView` gained swipe-to-remove (nullifies `video.category`, doesn't touch the `Category` record itself) and multi-select removal via `List(selection:)` + `EditButton()` for removing several at once. Either path's count update is free, per the point above.
    - Verified via `testCategorizeFromPlaybackAndRemoveFromLibrary`: create a category from the tray → it's selected and the tray closes → Library reflects it with count 1 → swipe-remove → count drops back to 0. Needed the same `isActive`-scoping fix as captionText/scrubber/videoIdentity for the new categorize button's accessibility identifier (the pre-rendered swipe-neighbor page has one alive too).

    **Bug found after shipping this**: the tray worked fine when playback was opened from any Library list, but opened-and-immediately-closed itself when opened from Home's "Recently Added" specifically. Root cause, found by tracing `onAppear`/`onDisappear` through the unified log (plain `print()` doesn't reach it — the app under XCUITest is a separate process from the test target, so only `NSLog`/`os_log` show up via `xcrun simctl spawn <device> log stream --process IGDL`): `PlaybackView` itself — not just its child pages — was being torn down and recreated a few hundred milliseconds after presenting *any* `.sheet()` from within it (independent of that sheet's own content — reproduced with a version of the category tray that didn't even use `@Query`), but only when the `.fullScreenCover` presenting it had been triggered from a row that's a **direct child of a `NavigationStack`'s root** (Home's Recently Added list). The identical `.fullScreenCover`, triggered from a row on a **pushed** view (Library → Videos → row), never showed this — confirmed HomeView's own `body` wasn't even re-evaluating during the failure, ruling out a SwiftData `@Query`-invalidation cascade. This point (root-vs-pushed presentation context) is as precise as the diagnosis got; the exact underlying UIKit/SwiftUI mechanism wasn't pinned down further.
    - **Fix**: stopped presenting playback per-row entirely. `PlaybackCoordinator` (`@Observable`, holding one `playback: PlayableList?`) is now created once at `RootTabView` and the *only* `.fullScreenCover` for playback lives there, keyed to `$coordinator.playback` (via `@Bindable`). Every `PlayableVideoRow` (used from Home, Videos, Playlists, Creators, and Categories alike) now just calls `coordinator.play(...)` through `@Environment(PlaybackCoordinator.self)` instead of owning a local `@State` + `.fullScreenCover` — one stable presentation site instead of one per row eliminates the root-vs-pushed asymmetry regardless of which list launched it. `PlaybackView`'s own category-tray state (`categorizingVideo`) stays where it was (unaffected once the outer view stopped being torn down). Verified via `testCategorizeFromRecentlyAddedOnHome`.
5. **Polish** — settings, sync status/progress UX, storage summary, delete-with-memory, failed-download retry.
6. **Incompatible videos** — PARTIAL. Found via a real user report: some downloads in a batch of 20-40 always fail, consistently, with no network involved — traced (via the backend's new resolve-lifecycle logging, see Backend Download Server) to `instagram.py` raising `ResolveError("post has no video")`. Root cause isn't a bug, it's a data mismatch: liked/saved libraries naturally include slideshow/carousel posts (no single video) alongside actual Reels, and the app currently queues everything as if it were downloadable, only discovering "this one has no video" at resolve time — a permanent, not-network-related failure that retrying can never fix.

    **Done (reactive, client-side only, no backend change needed)**: `BackendClient.checkStatus` now parses the response body's `detail` field (FastAPI's default `HTTPException` shape) instead of only reading the bare status code, so a failure surfaces its actual reason (e.g. "post has no video") rather than "Server returned 502" — shown under "Failed" same as any other error. `Video` gained `isVideo: Bool = true`; `DownloadManager` flips it to `false` the moment a resolve fails with exactly that message (`markIncompatibleIfNeeded`, string-matched against the backend's exact wording — a deliberately narrow, low-risk coupling). `DownloadView` now excludes `!isVideo` videos from both "Downloading" and "Ready for Download" entirely and lists them in their own read-only **"Not Reels (N)"** section at the bottom instead — since `selectFromTop`/`selectRandom` already draw from the same filtered `selectableVideos`, they never pick a known-incompatible post either, for free. Verified via `DownloadManagerTests` (mocks the backend response via a custom `URLProtocol`, no real network needed) — one asserting the flag flips and the message surfaces for "post has no video", another confirming an unrelated failure message does *not* misfire the same flag.

    **Still NEXT**: this only ever discovers a post is incompatible *after* a real resolve attempt fails once — it doesn't know ahead of time, and doesn't yet cover "video on a since-made-private profile" (a different failure signature at resolve time, not yet special-cased the same way). The originally-scoped fix is still worth doing: detect both categories at the **Retriever** (`main.py`) snapshot stage instead, threading a flag through `liked_snapshot.json`/`saved_snapshot.json` → `build_headers.py` → the headers file → `HeadersImporter` setting it on `Video` at import, so the Download screen already knows before ever attempting a resolve.
