import XCTest

final class IGDLUITests: XCTestCase {
    /// Drives the actual app UI through the DEBUG-only headers-file loading
    /// shortcut (see SyncView) and checks the import itself lands at scale —
    /// the one thing the unit tests (which exercise HeadersImporter
    /// directly, not through the UI) can't confirm on their own. Library and
    /// Home only show *downloaded* videos by design (header-only data isn't
    /// useful to show), so importing without downloading anything should
    /// leave both showing empty states, not the freshly-imported items.
    func testImportDebugHeadersFileAndRendersHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["Load repo headers.json (DEBUG)"].tap()

        let result = app.staticTexts["Imported 5218 items."]
        XCTAssertTrue(result.waitForExistence(timeout: 15))

        attachScreenshot(from: app, named: "sync-result")

        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["No videos yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Download New Videos'")).firstMatch.exists)
        attachScreenshot(from: app, named: "home-nothing-downloaded-yet")

        app.tabBars.buttons["Library"].tap()
        app.buttons["Videos"].tap()

        XCTAssertTrue(app.navigationBars["Videos (0)"].waitForExistence(timeout: 5))
        attachScreenshot(from: app, named: "library-videos-empty")
    }

    /// Drives the real Download screen against two known-good posts,
    /// downloading them for real over the network (backend resolves CDN
    /// URLs + comments, the app downloads video/cover directly from
    /// Instagram's CDN) — confirms both the UI status and the actual files
    /// landing in the app's sandbox.
    func testDownloadSelectedVideos() throws {
        let fixturePath = Bundle(for: Self.self).path(forResource: "small_headers_fixture", ofType: "json")!

        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launchEnvironment["IGDL_TEST_HEADERS_PATH"] = fixturePath
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["Load repo headers.json (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Imported 2 items."].waitForExistence(timeout: 15))
        app.buttons["Done"].tap()

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Download New Videos'")).firstMatch.tap()

        let shortCodes = ["DbvVH3RTq9w", "DcZS95wRUJ9"]
        for code in shortCodes {
            let checkbox = app.buttons["checkbox_\(code)"]
            XCTAssertTrue(checkbox.waitForExistence(timeout: 10), "row for \(code) should exist among pending videos")
            checkbox.tap()
        }

        attachScreenshot(from: app, named: "download-selected")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Download Selected'")).firstMatch.tap()

        // Grab a mid-flight shot of the "Downloading" section with real
        // per-item progress, before it's had time to complete.
        _ = app.staticTexts["Downloading"].waitForExistence(timeout: 5)
        attachScreenshot(from: app, named: "downloading-in-progress")

        // A successfully downloaded video sets fetched=true, which the
        // pending-only @Query in DownloadView immediately filters out. Since
        // the fixture is just these 2 items, once both finish the list goes
        // fully empty — a single clean signal instead of per-row polling.
        XCTAssertTrue(app.staticTexts["Nothing to download"].waitForExistence(timeout: 60))
        attachScreenshot(from: app, named: "download-complete")
    }

    /// Downloads the same 2 known posts as testDownloadSelectedVideos, then
    /// drives real playback: opens a video, expands/collapses comments, and
    /// dismisses back to the list — confirming the custom AVPlayer-based
    /// pager and its controls actually work, not just compile.
    func testPlaybackOpensExpandsCommentsAndDismisses() throws {
        let fixturePath = Bundle(for: Self.self).path(forResource: "small_headers_fixture", ofType: "json")!

        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launchEnvironment["IGDL_TEST_HEADERS_PATH"] = fixturePath
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["Load repo headers.json (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Imported 2 items."].waitForExistence(timeout: 15))
        app.buttons["Done"].tap()

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Download New Videos'")).firstMatch.tap()
        for code in ["DbvVH3RTq9w", "DcZS95wRUJ9"] {
            app.buttons["checkbox_\(code)"].tap()
        }
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Download Selected'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Nothing to download"].waitForExistence(timeout: 60))

        app.tabBars.buttons["Library"].tap()
        app.buttons["Videos"].tap()

        // .onTapGesture doesn't give the row a "Button" trait, so match any
        // element type rather than assuming which one SwiftUI exposed.
        let row = app.descendants(matching: .any).matching(identifier: "videoRow_DbvVH3RTq9w").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let dismissButton = app.buttons["playbackDismiss"]
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 10), "playback should open")
        attachScreenshot(from: app, named: "playback-normal")

        // Both the current page and its pre-rendered swipe-neighbor are
        // alive in the hierarchy at once (by design, for smooth paging), so
        // both have a "showComments" button — disambiguate by comment count
        // label (62 for DbvVH3RTq9w) rather than assuming .firstMatch hits
        // the on-screen one.
        app.buttons.matching(NSPredicate(format: "identifier == 'showComments' AND label == '62'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Comments"].waitForExistence(timeout: 5))
        attachScreenshot(from: app, named: "playback-comments-expanded")

        app.buttons["hideComments"].tap()
        XCTAssertFalse(app.staticTexts["Comments"].waitForExistence(timeout: 2))

        dismissButton.tap()
        XCTAssertTrue(app.navigationBars["Videos (2)"].waitForExistence(timeout: 5), "should return to the video list")
    }

    /// Verifies video playback never crops content, regardless of aspect
    /// ratio — uses a real pre-downloaded wide (1092x718, ~1.52:1) video
    /// seeded locally via the DEBUG fixture shortcut (see SyncView), so this
    /// needs no network/backend call at all. A wider-than-screen video
    /// should letterbox (bars above/below), never fill-and-crop.
    func testPlaybackFitsWideVideoWithoutCropping() throws {
        let headersFixturePath = Bundle(for: Self.self).path(forResource: "wide_video_headers_fixture", ofType: "json")!

        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launchEnvironment["IGDL_TEST_HEADERS_PATH"] = headersFixturePath
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["Load repo headers.json (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Imported 1 items."].waitForExistence(timeout: 15))

        app.buttons["Seed local fixture videos (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Seeded 1 fixture video(s)."].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        app.tabBars.buttons["Library"].tap()
        app.buttons["Videos"].tap()

        let row = app.descendants(matching: .any).matching(identifier: "videoRow_DdO34QFtmse").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.buttons["playbackDismiss"].waitForExistence(timeout: 10), "playback should open")
        // Give the player a moment to actually start rendering frames
        // before capturing, rather than screenshotting a black first frame.
        Thread.sleep(forTimeInterval: 2)
        attachScreenshot(from: app, named: "playback-wide-video-letterboxed")
    }

    /// Checks the aspect-fit behavior across a mix of real videos: one
    /// wide/landscape (DdO34QFtmse) and two normal Reels-shaped portrait
    /// videos (DbvVH3RTq9w, DcZS95wRUJ9) — confirming the portrait ones
    /// still look right (no unwanted cropping or excessive bars) now that
    /// .resizeAspect is used everywhere, not just checking the wide case in
    /// isolation.
    func testPlaybackAspectFitAcrossPortraitAndWideVideos() throws {
        let headersFixturePath = Bundle(for: Self.self).path(forResource: "aspect_ratio_fixture", ofType: "json")!

        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launchEnvironment["IGDL_TEST_HEADERS_PATH"] = headersFixturePath
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["Load repo headers.json (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Imported 3 items."].waitForExistence(timeout: 15))

        app.buttons["Seed local fixture videos (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Seeded 3 fixture video(s)."].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        app.tabBars.buttons["Library"].tap()
        app.buttons["Videos"].tap()

        // Open each portrait video directly by tapping its own row (rather
        // than swiping within one playback session — a swipeUp() there
        // turned out to not reliably register as a real page-change
        // gesture, silently just re-screenshotting the same video later
        // into its loop instead of a different one).
        for shortCode in ["DbvVH3RTq9w", "DcZS95wRUJ9"] {
            let row = app.descendants(matching: .any).matching(identifier: "videoRow_\(shortCode)").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()

            XCTAssertTrue(app.buttons["playbackDismiss"].waitForExistence(timeout: 10), "playback should open for \(shortCode)")
            Thread.sleep(forTimeInterval: 2)
            attachScreenshot(from: app, named: "playback-\(shortCode)")

            app.buttons["playbackDismiss"].tap()
            XCTAssertTrue(app.navigationBars["Videos (3)"].waitForExistence(timeout: 5))
        }
    }

    /// Verifies the scrubber renders and responds to a drag — uses the same
    /// locally-seeded fixture videos as the aspect-ratio test, no network
    /// needed. Screenshots before/after a drag to the far right, and checks
    /// the underlying player's time actually moved as a result (not just
    /// that the drag gesture didn't crash).
    func testPlaybackScrubberDragSeeks() throws {
        let headersFixturePath = Bundle(for: Self.self).path(forResource: "aspect_ratio_fixture", ofType: "json")!

        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launchEnvironment["IGDL_TEST_HEADERS_PATH"] = headersFixturePath
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["Load repo headers.json (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Imported 3 items."].waitForExistence(timeout: 15))
        app.buttons["Seed local fixture videos (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Seeded 3 fixture video(s)."].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        app.tabBars.buttons["Library"].tap()
        app.buttons["Videos"].tap()

        let row = app.descendants(matching: .any).matching(identifier: "videoRow_DbvVH3RTq9w").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["playbackDismiss"].waitForExistence(timeout: 10))

        // Let real playback advance a moment so the scrubber has a nonzero
        // starting position before we drag it — otherwise a drag-to-far-left
        // wouldn't visibly prove anything moved.
        Thread.sleep(forTimeInterval: 2)

        // Only the active page's element is identified as "scrubber" (see
        // PlaybackPageView) — the pre-rendered swipe-neighbor page has one
        // too, so this would be ambiguous otherwise.
        let scrubber = app.otherElements["scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        attachScreenshot(from: app, named: "scrubber-before-drag")

        // Drag from the scrubber's own start to its own end coordinate,
        // rather than a screen-relative offset, so this doesn't depend on
        // where the bar happens to sit on this device's screen.
        let start = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        let end = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)

        attachScreenshot(from: app, named: "scrubber-after-drag")
    }

    /// Regression test for a bug where swiping to advance to the next video
    /// instead paused the current one — every gesture tried on the video
    /// area before landing on a plain .onTapGesture (see
    /// PlaybackPageView.videoArea) had this failure mode in one form or
    /// another. A discrete tap gesture naturally doesn't fire for a large
    /// drag (it requires minimal movement to recognize at all), but this
    /// stays as a regression guard against a future change reintroducing
    /// continuous tracking here.
    ///
    /// Doesn't assert the ScrollView actually pages to the next video —
    /// XCUITest's synthetic drags are known to not reliably trigger a real
    /// page transition against this specific pager even when the app-level
    /// behavior is correct (confirmed directly on-device instead — see
    /// testPlaybackAspectFitAcrossPortraitAndWideVideos, which works around
    /// the same limitation by opening videos directly rather than swiping
    /// between them).
    func testLargeVerticalDragDoesNotPauseVideo() throws {
        let headersFixturePath = Bundle(for: Self.self).path(forResource: "aspect_ratio_fixture", ofType: "json")!

        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launchEnvironment["IGDL_TEST_HEADERS_PATH"] = headersFixturePath
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["Load repo headers.json (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Imported 3 items."].waitForExistence(timeout: 15))
        app.buttons["Seed local fixture videos (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Seeded 3 fixture video(s)."].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        app.tabBars.buttons["Library"].tap()
        app.buttons["Videos"].tap()

        let row = app.descendants(matching: .any).matching(identifier: "videoRow_DbvVH3RTq9w").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["playbackDismiss"].waitForExistence(timeout: 10))

        let startIdentity = app.descendants(matching: .any).matching(identifier: "videoIdentity_DbvVH3RTq9w").firstMatch
        XCTAssertTrue(startIdentity.waitForExistence(timeout: 5))
        attachScreenshot(from: app, named: "swipe-before")

        // Quick drag (not held), matching a real flick rather than a
        // press-and-hold — holding first risks tripping the long-press-to-2x
        // path instead of exercising a plain swipe.
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.0)
        attachScreenshot(from: app, named: "swipe-after")

        let pausedIcon = app.images.matching(identifier: "pausedIcon").firstMatch
        XCTAssertFalse(pausedIcon.exists, "a large vertical drag (swipe) should not pause the video")
    }

    /// Verifies tap-to-pause (a plain .onTapGesture on the video area — see
    /// PlaybackPageView.videoArea for why it's deliberately just a tap, no
    /// long-press-to-2x: every gesture that continuously tracks a touch
    /// there, including a LongPressGesture+.updating attempt, broke
    /// PlaybackView's swipe-to-advance pager) and that swipe-to-dismiss (a
    /// horizontal drag on the *parent* view) still works alongside it.
    func testTapPausesWithoutBreakingDismiss() throws {
        let headersFixturePath = Bundle(for: Self.self).path(forResource: "aspect_ratio_fixture", ofType: "json")!

        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launchEnvironment["IGDL_TEST_HEADERS_PATH"] = headersFixturePath
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["Load repo headers.json (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Imported 3 items."].waitForExistence(timeout: 15))
        app.buttons["Seed local fixture videos (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Seeded 3 fixture video(s)."].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        app.tabBars.buttons["Library"].tap()
        app.buttons["Videos"].tap()

        let row = app.descendants(matching: .any).matching(identifier: "videoRow_DbvVH3RTq9w").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["playbackDismiss"].waitForExistence(timeout: 10))

        let videoPoint = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let pausedIcon = app.images.matching(identifier: "pausedIcon").firstMatch

        videoPoint.tap()
        XCTAssertTrue(pausedIcon.waitForExistence(timeout: 3), "tap should pause")
        videoPoint.tap()
        XCTAssertFalse(pausedIcon.waitForExistence(timeout: 2), "second tap should resume")

        // Swipe-to-dismiss (horizontal drag on the parent PlaybackView) must
        // still work now that the video view itself owns a gesture too.
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.navigationBars["Videos (3)"].waitForExistence(timeout: 5), "swipe-right should dismiss back to the list")
    }

    /// Verifies video_duration flows all the way from the headers file to a
    /// visible "M:SS" label on the Download screen — this needs no local
    /// media files (the Download screen shows *pending*, not-yet-fetched
    /// videos), just a headers import.
    func testDownloadScreenShowsVideoDuration() throws {
        let headersFixturePath = Bundle(for: Self.self).path(forResource: "duration_fixture", ofType: "json")!

        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launchEnvironment["IGDL_TEST_HEADERS_PATH"] = headersFixturePath
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["Load repo headers.json (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Imported 1 items."].waitForExistence(timeout: 15))
        app.buttons["Done"].tap()

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Download New Videos'")).firstMatch.tap()

        // 176.133s -> 2:56.
        XCTAssertTrue(app.staticTexts["2:56"].waitForExistence(timeout: 5), "duration should render as M:SS on the Download screen")
        attachScreenshot(from: app, named: "download-screen-duration")
    }

    /// Regression test for the bug where tapping the caption (or dragging
    /// the scrubber) also paused the video underneath, once the video
    /// area's own gesture became .onLongPressGesture (for long-press-to-2x)
    /// instead of a plain .onTapGesture.
    func testCaptionTapAndScrubberDragDoNotPauseVideo() throws {
        let headersFixturePath = Bundle(for: Self.self).path(forResource: "aspect_ratio_fixture", ofType: "json")!

        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launchEnvironment["IGDL_TEST_HEADERS_PATH"] = headersFixturePath
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["Load repo headers.json (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Imported 3 items."].waitForExistence(timeout: 15))
        app.buttons["Seed local fixture videos (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Seeded 3 fixture video(s)."].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        app.tabBars.buttons["Library"].tap()
        app.buttons["Videos"].tap()

        let row = app.descendants(matching: .any).matching(identifier: "videoRow_DbvVH3RTq9w").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["playbackDismiss"].waitForExistence(timeout: 10))

        let pausedIcon = app.images.matching(identifier: "pausedIcon").firstMatch
        // A Text view exposes as StaticText, not Other — match any type
        // rather than assuming, same as the videoRow_ lookups elsewhere.
        let caption = app.descendants(matching: .any).matching(identifier: "captionText").firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5))

        caption.tap()
        // Give the tap's effect (or lack thereof) a moment to settle before
        // asserting absence — waitForExistence(timeout: 0) could pass
        // trivially before any gesture has actually resolved.
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(pausedIcon.exists, "tapping the caption should not pause the video")

        let scrubber = app.otherElements["scrubber"]
        let dragStart = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let dragEnd = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(pausedIcon.exists, "dragging the scrubber should not pause the video")

        attachScreenshot(from: app, named: "caption-and-scrubber-no-pause")
    }

    /// Verifies the Select… menu's "20 from top"/"20 random" options are
    /// additive (repeated taps add more, never re-select or double-count
    /// what's already selected) and that the running-total bar reflects it.
    /// Fixture has only 3 pending videos, so "20 from top" naturally selects
    /// "all 3, then nothing more" — exercises the same unselected-only
    /// filtering logic a real 20+-video library would, without needing a
    /// large fixture.
    func testSelectMenuAddsWithoutDuplicating() throws {
        let headersFixturePath = Bundle(for: Self.self).path(forResource: "aspect_ratio_fixture", ofType: "json")!

        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launchEnvironment["IGDL_TEST_HEADERS_PATH"] = headersFixturePath
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["Load repo headers.json (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Imported 3 items."].waitForExistence(timeout: 15))
        app.buttons["Done"].tap()

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Download New Videos'")).firstMatch.tap()

        XCTAssertTrue(app.staticTexts["0 selected"].waitForExistence(timeout: 5))

        app.buttons["selectMenu"].tap()
        app.buttons["select20FromTop"].tap()
        XCTAssertTrue(app.staticTexts["3 selected"].waitForExistence(timeout: 5), "should select all 3 available (fewer than 20 exist)")
        XCTAssertTrue(app.buttons["Download Selected (3)"].waitForExistence(timeout: 5))

        // Tapping again should add nothing — all 3 are already selected,
        // so there's nothing left unselected to add.
        app.buttons["selectMenu"].tap()
        app.buttons["select20FromTop"].tap()
        XCTAssertTrue(app.staticTexts["3 selected"].waitForExistence(timeout: 5), "re-tapping with nothing left unselected should not change the count")

        // Deselect one, then "20 random" should pick it back up (only
        // candidate left) without duplicating the other two.
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'checkbox_'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["2 selected"].waitForExistence(timeout: 5))

        app.buttons["selectMenu"].tap()
        app.buttons["select20Random"].tap()
        XCTAssertTrue(app.staticTexts["3 selected"].waitForExistence(timeout: 5), "20 random should fill back in from the only unselected video")

        attachScreenshot(from: app, named: "select-menu-running-total")
    }

    /// End-to-end coverage for the categorize feature: creating a category
    /// from the playback screen's tray, selecting it (closes the tray),
    /// seeing it reflected in the Library's Categories view with the right
    /// count, then removing the video from it via swipe (count goes back to
    /// zero) — the two places categories can change, per the feature spec.
    func testCategorizeFromPlaybackAndRemoveFromLibrary() throws {
        let headersFixturePath = Bundle(for: Self.self).path(forResource: "aspect_ratio_fixture", ofType: "json")!

        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launchEnvironment["IGDL_TEST_HEADERS_PATH"] = headersFixturePath
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["Load repo headers.json (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Imported 3 items."].waitForExistence(timeout: 15))
        app.buttons["Seed local fixture videos (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Seeded 3 fixture video(s)."].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        app.tabBars.buttons["Library"].tap()
        app.buttons["Videos"].tap()

        let row = app.descendants(matching: .any).matching(identifier: "videoRow_DbvVH3RTq9w").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["playbackDismiss"].waitForExistence(timeout: 10))

        // Open the tray and create a brand new category.
        app.buttons["categorizeButton"].tap()
        XCTAssertTrue(app.buttons["addCategoryButton"].waitForExistence(timeout: 5))
        app.buttons["addCategoryButton"].tap()

        let nameField = app.textFields["Category name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Comedy")
        // Scoped to the alert specifically — the "+" button underneath also
        // resolves to an "Add" accessibility label (auto-derived from its
        // SF Symbol), ambiguous with the alert's own Add action otherwise.
        app.alerts["New Category"].buttons["Add"].tap()

        // Creating it should select it immediately and close the tray.
        XCTAssertTrue(app.buttons["playbackDismiss"].waitForExistence(timeout: 5), "tray should close after adding a category")
        attachScreenshot(from: app, named: "categorized-video")

        // Reopening the tray should show the new category checked, above
        // "None" at the bottom.
        app.buttons["categorizeButton"].tap()
        let categoryRow = app.buttons["categoryRow_Comedy"]
        XCTAssertTrue(categoryRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["categoryRow_None"].exists)
        // Dismiss the tray without changing anything.
        app.swipeDown(velocity: .fast)

        app.buttons["playbackDismiss"].tap()

        // Library should reflect the new category with a count of 1.
        app.tabBars.buttons["Library"].tap()
        app.buttons["Categories"].tap()
        XCTAssertTrue(app.staticTexts["Comedy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1"].waitForExistence(timeout: 5))

        app.staticTexts["Comedy"].tap()
        let categorizedRow = app.descendants(matching: .any).matching(identifier: "videoRow_DbvVH3RTq9w").firstMatch
        XCTAssertTrue(categorizedRow.waitForExistence(timeout: 5))

        // Swipe-to-remove takes it back out of the category.
        categorizedRow.swipeLeft()
        app.buttons["Remove"].tap()
        XCTAssertFalse(categorizedRow.waitForExistence(timeout: 5), "video should be gone from the category after removing")

        app.navigationBars.buttons.firstMatch.tap() // back to Categories
        XCTAssertTrue(app.staticTexts["0"].waitForExistence(timeout: 5), "count should drop back to 0 after removal")
    }

    /// Diagnostic for a reported bug: the category tray is buggy when
    /// playback is opened from Home's "Recently Added" list specifically,
    /// while working fine from Library lists. Mirrors
    /// testCategorizeFromPlaybackAndRemoveFromLibrary but opens the video
    /// directly from Home instead of navigating into Library first.
    func testCategorizeFromRecentlyAddedOnHome() throws {
        let headersFixturePath = Bundle(for: Self.self).path(forResource: "aspect_ratio_fixture", ofType: "json")!

        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launchEnvironment["IGDL_TEST_HEADERS_PATH"] = headersFixturePath
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["Load repo headers.json (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Imported 3 items."].waitForExistence(timeout: 15))
        app.buttons["Seed local fixture videos (DEBUG)"].tap()
        XCTAssertTrue(app.staticTexts["Seeded 3 fixture video(s)."].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        // Stay on Home — don't navigate to Library at all. This is the
        // regression case: playback presented from a row that's a direct
        // child of Home's own NavigationStack root (as opposed to a row on
        // a *pushed* view, like Library → Videos) — see PlaybackCoordinator
        // for why that distinction used to matter.
        let row = app.descendants(matching: .any).matching(identifier: "videoRow_DbvVH3RTq9w").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "should appear directly in Recently Added on Home")
        row.tap()
        XCTAssertTrue(app.buttons["playbackDismiss"].waitForExistence(timeout: 10))

        app.buttons["categorizeButton"].tap()
        XCTAssertTrue(app.buttons["addCategoryButton"].waitForExistence(timeout: 5), "tray should open and stay open")
        app.buttons["addCategoryButton"].tap()

        let nameField = app.textFields["Category name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Comedy")
        app.alerts["New Category"].buttons["Add"].tap()

        XCTAssertTrue(app.buttons["playbackDismiss"].waitForExistence(timeout: 5), "tray should close after adding a category")
        attachScreenshot(from: app, named: "categorized-from-home")
    }

    private func attachScreenshot(from app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
