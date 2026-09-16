import Foundation
import SwiftData

enum HeadersImporter {
    static let savedPlaylistName = "Saved"
    static let authenticatedUsernameDefaultsKey = "authenticatedUserUsername"

    /// Parses a headers file and upserts every item into the store by `pk`.
    /// Returns the number of items processed.
    @discardableResult
    static func importFile(at url: URL, context: ModelContext) throws -> Int {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if needsSecurityScope { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        return try importData(data, context: context)
    }

    @discardableResult
    static func importData(_ data: Data, context: ModelContext) throws -> Int {
        let headers = try JSONDecoder().decode(HeadersFile.self, from: data)
        UserDefaults.standard.set(headers.authenticatedUserUsername, forKey: authenticatedUsernameDefaultsKey)
        let savedPlaylist = try fetchOrCreateSavedPlaylist(context: context)

        // One bulk fetch instead of a FetchDescriptor per item — with
        // thousands of items, N individual queries is the difference
        // between this taking under a second and tens of seconds.
        let existingVideos = try context.fetch(FetchDescriptor<Video>())
        var byPk = Dictionary(uniqueKeysWithValues: existingVideos.map { ($0.pk, $0) })

        for item in headers.items {
            let video = upsertVideo(from: item, existing: byPk[item.pk], savedPlaylist: savedPlaylist, context: context)
            byPk[item.pk] = video
        }

        try context.save()
        return headers.items.count
    }

    private static func fetchOrCreateSavedPlaylist(context: ModelContext) throws -> Playlist {
        let name = savedPlaylistName
        let descriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.name == name })
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let playlist = Playlist(name: name, isBuiltIn: true)
        context.insert(playlist)
        return playlist
    }

    @discardableResult
    private static func upsertVideo(
        from item: HeadersFileItem,
        existing: Video?,
        savedPlaylist: Playlist,
        context: ModelContext
    ) -> Video {
        let video: Video
        if let existing {
            video = existing
            video.shortCode = item.shortCode
            video.originalWidth = item.originalWidth
            video.originalHeight = item.originalHeight
            video.videoDuration = item.videoDuration
            video.likeCount = item.likeCount
            video.captionText = item.captionText
            video.commentCount = item.commentCount
            video.username = item.username
            video.userPk = item.userPk
            video.userProfilePicURL = item.userProfilePicURL
            video.takenAt = item.takenAt
            video.sources = item.sources
        } else {
            video = Video(
                pk: item.pk,
                shortCode: item.shortCode,
                originalWidth: item.originalWidth,
                originalHeight: item.originalHeight,
                videoDuration: item.videoDuration,
                likeCount: item.likeCount,
                captionText: item.captionText,
                commentCount: item.commentCount,
                username: item.username,
                userPk: item.userPk,
                userProfilePicURL: item.userProfilePicURL,
                takenAt: item.takenAt,
                sources: item.sources
            )
            context.insert(video)
        }

        // Applied on every upsert, not just creation: a video that becomes
        // "saved" on a later sync should join the Saved playlist then, even
        // if it was already imported as liked-only before. Never removed
        // automatically (e.g. on unsave) — this is a default, not a sync.
        if item.sources.contains("saved"), !video.playlists.contains(where: { $0.name == savedPlaylistName }) {
            video.playlists.append(savedPlaylist)
        }

        return video
    }
}
