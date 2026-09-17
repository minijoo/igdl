import XCTest
@testable import IGDL

final class PlaybackQueueTests: XCTestCase {
    private func makeVideo(_ shortCode: String, fetched: Bool = true) -> Video {
        Video(
            pk: shortCode,
            shortCode: shortCode,
            originalWidth: nil,
            originalHeight: nil,
            videoDuration: nil,
            likeCount: 0,
            captionText: nil,
            commentCount: 0,
            username: "user",
            userPk: "user_pk",
            userProfilePicURL: nil,
            takenAt: 0,
            sources: [],
            fetched: fetched
        )
    }

    /// A fixed (non-shuffle) queue never had a reserve to begin with —
    /// ensureBuffer should be a harmless no-op no matter how it's called,
    /// which is what every existing (Library/Playlists/Categories/Creators)
    /// playback entry point relies on.
    func testFixedQueueDoesNotGrow() {
        let videos = (0..<5).map { makeVideo("v\($0)") }
        let queue = PlaybackQueue(videos: videos, startIndex: 2)

        queue.ensureBuffer(current: 4)
        queue.ensureBuffer(current: 4)

        XCTAssertEqual(queue.videos.count, 5)
        XCTAssertEqual(queue.startIndex, 2)
    }

    /// Shuffle-all starts with just a handful dealt out, not the whole pool.
    func testShuffleQueueStartsWithOnlyInitialCount() {
        let pool = (0..<50).map { makeVideo("v\($0)") }
        let queue = PlaybackQueue(shuffling: pool, initialCount: 5)

        XCTAssertEqual(queue.videos.count, 5)
        XCTAssertEqual(queue.startIndex, 0)
    }

    /// As playback advances near the end of what's loaded, more videos from
    /// the pool should get appended automatically.
    func testShuffleQueueGrowsAsPlaybackAdvances() {
        let pool = (0..<50).map { makeVideo("v\($0)") }
        let queue = PlaybackQueue(shuffling: pool, initialCount: 5)

        queue.ensureBuffer(current: 4, lookahead: 3)
        XCTAssertGreaterThan(queue.videos.count, 5, "advancing near the end of the loaded batch should top it back up")
    }

    /// The whole point of dealing from one upfront shuffle rather than
    /// picking randomly on each call: a video can never be queued twice,
    /// with no extra "already seen" bookkeeping needed.
    func testShuffleQueueNeverRepeatsAVideo() {
        let pool = (0..<30).map { makeVideo("v\($0)") }
        let queue = PlaybackQueue(shuffling: pool, initialCount: 4)

        for index in 0..<25 {
            queue.ensureBuffer(current: min(index, queue.videos.count - 1), lookahead: 3)
        }

        let shortCodes = queue.videos.map(\.shortCode)
        XCTAssertEqual(Set(shortCodes).count, shortCodes.count, "no video should ever appear twice in the queue")
        XCTAssertLessThanOrEqual(shortCodes.count, pool.count, "can never grow past the size of the whole pool")
    }

    /// A pool smaller than the requested initial batch should just play
    /// everything, not crash.
    func testShuffleQueueHandlesPoolSmallerThanInitialCount() {
        let pool = (0..<3).map { makeVideo("v\($0)") }
        let queue = PlaybackQueue(shuffling: pool, initialCount: 5)

        XCTAssertEqual(queue.videos.count, 3)
        queue.ensureBuffer(current: 2, lookahead: 3)
        XCTAssertEqual(queue.videos.count, 3, "nothing left in reserve to grow into")
    }

    func testPlayableQueueFiltersToFetchedAndFindsStartIndex() throws {
        let videos = [
            makeVideo("a", fetched: true),
            makeVideo("b", fetched: false),
            makeVideo("c", fetched: true),
        ]

        let queue = try XCTUnwrap(videos.playableQueue(startingAt: videos[2]))

        XCTAssertEqual(queue.videos.map(\.shortCode), ["a", "c"])
        XCTAssertEqual(queue.startIndex, 1)
    }
}
