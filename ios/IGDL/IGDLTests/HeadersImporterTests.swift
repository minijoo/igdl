import XCTest
import SwiftData
@testable import IGDL

final class HeadersImporterTests: XCTestCase {
    func makeContext() throws -> ModelContext {
        let schema = Schema([Video.self, Category.self, Playlist.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// Runs the importer against the real headers.json produced by
    /// build_headers.py, checked against known counts (5218 items, 421 of
    /// which have "saved" in sources) so this breaks if the real file's
    /// shape or the importer's field mapping drifts.
    func testImportRealHeadersFile() throws {
        let url = URL(fileURLWithPath: "/Users/jordy/workspace/igdl/headers.json")
        let data = try Data(contentsOf: url)
        let context = try makeContext()

        let count = try HeadersImporter.importData(data, context: context)
        XCTAssertEqual(count, 5218)

        let allVideos = try context.fetch(FetchDescriptor<Video>())
        XCTAssertEqual(allVideos.count, 5218)

        let savedDescriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.name == "Saved" })
        let savedPlaylist = try context.fetch(savedDescriptor).first
        XCTAssertNotNil(savedPlaylist)
        XCTAssertEqual(savedPlaylist?.videos.count, 421)

        // A post synced after video_duration capture was added should have
        // a real value; formattedDuration should render it as "M:SS".
        let withDurationDescriptor = FetchDescriptor<Video>(
            predicate: #Predicate { $0.pk == "3986264426260405936" }
        )
        let withDuration = try XCTUnwrap(context.fetch(withDurationDescriptor).first)
        let duration = try XCTUnwrap(withDuration.videoDuration)
        XCTAssertEqual(duration, 176.13299560546875, accuracy: 0.001)
        XCTAssertEqual(withDuration.formattedDuration, "2:56")

        // Known post with sources ["liked", "saved"] — must land in Saved.
        let bothDescriptor = FetchDescriptor<Video>(
            predicate: #Predicate { $0.pk == "3983178425050503111" }
        )
        let bothVideo = try context.fetch(bothDescriptor).first
        XCTAssertNotNil(bothVideo)
        XCTAssertTrue(bothVideo?.playlists.contains(where: { $0.name == "Saved" }) ?? false)

        // Known liked-only post — must NOT get a default playlist.
        let likedOnlyDescriptor = FetchDescriptor<Video>(
            predicate: #Predicate { $0.pk == "3897750621442589142" }
        )
        let likedOnlyVideo = try context.fetch(likedOnlyDescriptor).first
        XCTAssertNotNil(likedOnlyVideo)
        XCTAssertTrue(likedOnlyVideo?.playlists.isEmpty ?? false)
    }

    func testReImportUpsertsAndAppliesDefaultPlaylistRetroactively() throws {
        let context = try makeContext()

        let likedOnlyJSON = Data("""
        {
            "retrieved_at": 1,
            "authenticated_user_username": "test",
            "items": [{
                "pk": "1", "short_code": "abc", "original_width": null, "original_height": null,
                "like_count": 1, "caption_text": null, "comment_count": 0,
                "username": "u", "user_pk": "1", "user_profile_pic_url": null,
                "taken_at": 1, "sources": ["liked"]
            }]
        }
        """.utf8)

        try HeadersImporter.importData(likedOnlyJSON, context: context)
        var videos = try context.fetch(FetchDescriptor<Video>())
        XCTAssertEqual(videos.count, 1)
        XCTAssertTrue(videos[0].playlists.isEmpty)

        // Same post, re-synced later now also saved — should retroactively
        // join Saved without creating a duplicate row.
        let nowSavedTooJSON = Data("""
        {
            "retrieved_at": 2,
            "authenticated_user_username": "test",
            "items": [{
                "pk": "1", "short_code": "abc", "original_width": null, "original_height": null,
                "like_count": 2, "caption_text": null, "comment_count": 0,
                "username": "u", "user_pk": "1", "user_profile_pic_url": null,
                "taken_at": 1, "sources": ["liked", "saved"]
            }]
        }
        """.utf8)

        try HeadersImporter.importData(nowSavedTooJSON, context: context)
        videos = try context.fetch(FetchDescriptor<Video>())
        XCTAssertEqual(videos.count, 1, "should upsert by pk, not duplicate")
        XCTAssertEqual(videos[0].likeCount, 2, "should refresh fields on existing row")
        XCTAssertTrue(videos[0].playlists.contains(where: { $0.name == "Saved" }))
    }
}
