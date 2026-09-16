import Foundation
import SwiftData

@Model
final class Video {
    @Attribute(.unique) var pk: String
    var shortCode: String
    var originalWidth: Int?
    var originalHeight: Int?
    var videoDuration: Double? // seconds; nil for photo posts and pre-existing synced items
    var likeCount: Int
    var captionText: String?
    var commentCount: Int
    var username: String
    var userPk: String
    var userProfilePicURL: String?
    var takenAt: Int
    var sources: [String]
    var fetched: Bool

    var category: Category?
    var playlists: [Playlist] = []

    init(
        pk: String,
        shortCode: String,
        originalWidth: Int?,
        originalHeight: Int?,
        videoDuration: Double?,
        likeCount: Int,
        captionText: String?,
        commentCount: Int,
        username: String,
        userPk: String,
        userProfilePicURL: String?,
        takenAt: Int,
        sources: [String],
        fetched: Bool = false
    ) {
        self.pk = pk
        self.shortCode = shortCode
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.videoDuration = videoDuration
        self.likeCount = likeCount
        self.captionText = captionText
        self.commentCount = commentCount
        self.username = username
        self.userPk = userPk
        self.userProfilePicURL = userProfilePicURL
        self.takenAt = takenAt
        self.sources = sources
        self.fetched = fetched
    }

    /// "M:SS", e.g. "1:15" for 75.3 seconds. Nil when duration isn't known.
    var formattedDuration: String? {
        guard let videoDuration else { return nil }
        let totalSeconds = Int(videoDuration.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
