import XCTest
import SwiftData
@testable import IGDL

/// Returns a canned response for every request — lets these tests exercise
/// the real BackendClient/DownloadManager pipeline without hitting the real
/// network or the real backend.
private final class MockURLProtocol: URLProtocol {
    static var responseProvider: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let provider = Self.responseProvider, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (response, data) = provider(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
        _ = url
    }

    override func stopLoading() {}
}

final class DownloadManagerTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Video.self, Category.self, Playlist.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeMockClient(statusCode: Int, body: [String: String]) -> BackendClient {
        MockURLProtocol.responseProvider = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (response, try! JSONEncoder().encode(body))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return BackendClient(baseURL: URL(string: "https://example.invalid")!, session: URLSession(configuration: config))
    }

    /// Regression test for a real report: some resolves fail permanently
    /// with the backend's exact "post has no video" message (a
    /// slideshow/carousel post, not an actual Reel — see docs/plan.md's
    /// "Incompatible videos" item), not because of a network/timeout issue.
    /// DownloadManager should surface that message under the failed state
    /// *and* flip `Video.isVideo` to false so the Download screen can file
    /// it under "Not Reels" from then on instead of leaving it to fail the
    /// same way every time it's reselected.
    @MainActor
    func testResolveFailureWithNoVideoMessageMarksVideoIncompatible() async throws {
        let context = try makeContext()
        let video = Video(
            pk: "p1", shortCode: "abc123", originalWidth: nil, originalHeight: nil,
            videoDuration: nil, likeCount: 0, captionText: nil, commentCount: 0,
            username: "user", userPk: "u1", userProfilePicURL: nil, takenAt: 0, sources: []
        )
        context.insert(video)
        try context.save()
        XCTAssertTrue(video.isVideo)

        let client = makeMockClient(statusCode: 502, body: ["detail": "post has no video"])
        let manager = DownloadManager(client: client, coordinator: .shared)

        await manager.downloadSelected(shortCodes: ["abc123"], context: context)

        XCTAssertFalse(video.isVideo, "a slideshow/carousel post should be flagged incompatible")
        guard case .failed(let message) = manager.state(for: "abc123") else {
            return XCTFail("expected a failed state")
        }
        XCTAssertEqual(message, "post has no video", "the actual backend reason should be surfaced, not a bare status code")
    }

    /// A genuinely transient failure (unrelated status code/message) should
    /// not misfire the same permanent flag.
    @MainActor
    func testUnrelatedResolveFailureDoesNotMarkVideoIncompatible() async throws {
        let context = try makeContext()
        let video = Video(
            pk: "p2", shortCode: "def456", originalWidth: nil, originalHeight: nil,
            videoDuration: nil, likeCount: 0, captionText: nil, commentCount: 0,
            username: "user", userPk: "u1", userProfilePicURL: nil, takenAt: 0, sources: []
        )
        context.insert(video)
        try context.save()

        let client = makeMockClient(statusCode: 503, body: ["detail": "some transient upstream error"])
        let manager = DownloadManager(client: client, coordinator: .shared)

        await manager.downloadSelected(shortCodes: ["def456"], context: context)

        XCTAssertTrue(video.isVideo, "an unrelated failure should not be treated as a permanently incompatible post")
        guard case .failed(let message) = manager.state(for: "def456") else {
            return XCTFail("expected a failed state")
        }
        XCTAssertEqual(message, "some transient upstream error")
    }
}
