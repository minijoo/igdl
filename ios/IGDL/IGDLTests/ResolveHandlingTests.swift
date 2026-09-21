import XCTest
import SwiftData
@testable import IGDL

/// Tests ResolveHandling's pure SwiftData-mutating functions directly,
/// against a plain in-memory ModelContext — no network involved. Resolve
/// itself now runs as a background URLSessionDownloadTask inside
/// BackgroundDownloadCoordinator (see docs/plan.md), which isn't
/// realistically unit-testable (background transfers run in a separate
/// system process); ResolveHandling was deliberately pulled out as plain
/// functions specifically so the logic that matters here — what happens to
/// the database once a resolve result comes back — stays fast and
/// deterministic to test.
final class ResolveHandlingTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Video.self, Category.self, Playlist.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeVideo(_ shortCode: String) -> Video {
        Video(
            pk: shortCode, shortCode: shortCode, originalWidth: nil, originalHeight: nil,
            videoDuration: nil, likeCount: 0, captionText: nil, commentCount: 0,
            username: "user", userPk: "u1", userProfilePicURL: nil, takenAt: 0, sources: []
        )
    }

    /// Regression test for a real report: some resolves fail permanently
    /// with the backend's exact "post has no video" message (a
    /// slideshow/carousel post, not an actual Reel), not because of a
    /// network/timeout issue. This should flip Video.isVideo to false so
    /// the Download screen can file it under "Not Reels" from then on.
    func testMarkIncompatibleIfNeededFlipsIsVideoForExactMessage() throws {
        let context = try makeContext()
        let video = makeVideo("abc123")
        context.insert(video)
        try context.save()
        XCTAssertTrue(video.isVideo)

        ResolveHandling.markIncompatibleIfNeeded(shortCode: "abc123", message: "post has no video", context: context)

        XCTAssertFalse(video.isVideo)
    }

    /// A genuinely transient failure (unrelated message, or none at all —
    /// e.g. a plain network error) should not misfire the same permanent
    /// flag.
    func testMarkIncompatibleIfNeededIgnoresUnrelatedMessage() throws {
        let context = try makeContext()
        let video = makeVideo("def456")
        context.insert(video)
        try context.save()

        ResolveHandling.markIncompatibleIfNeeded(shortCode: "def456", message: "some transient upstream error", context: context)
        ResolveHandling.markIncompatibleIfNeeded(shortCode: "def456", message: nil, context: context)

        XCTAssertTrue(video.isVideo)
    }

    func testSaveMetadataUpdatesCaptionFromResolvedPost() throws {
        let context = try makeContext()
        let video = makeVideo("ghi789")
        video.captionText = "stale headers-file caption"
        context.insert(video)
        try context.save()

        let resolved = ResolvedPost(
            shortCode: "ghi789",
            videoURL: URL(string: "https://example.com/video.mp4")!,
            coverURL: URL(string: "https://example.com/cover.jpg")!,
            caption: "  fresh caption from the backend  ",
            comments: []
        )

        try ResolveHandling.saveMetadata(resolved: resolved, context: context)

        XCTAssertEqual(video.captionText, "fresh caption from the backend")
    }

    func testSaveMetadataLeavesCaptionAloneWhenResolvedCaptionIsEmpty() throws {
        let context = try makeContext()
        let video = makeVideo("jkl012")
        video.captionText = "keep me"
        context.insert(video)
        try context.save()

        let resolved = ResolvedPost(
            shortCode: "jkl012",
            videoURL: URL(string: "https://example.com/video.mp4")!,
            coverURL: URL(string: "https://example.com/cover.jpg")!,
            caption: "   ",
            comments: []
        )

        try ResolveHandling.saveMetadata(resolved: resolved, context: context)

        XCTAssertEqual(video.captionText, "keep me")
    }
}
