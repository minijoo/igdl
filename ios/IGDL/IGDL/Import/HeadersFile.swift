import Foundation

struct HeadersFile: Codable {
    let retrievedAt: Int
    let authenticatedUserUsername: String
    let items: [HeadersFileItem]

    enum CodingKeys: String, CodingKey {
        case retrievedAt = "retrieved_at"
        case authenticatedUserUsername = "authenticated_user_username"
        case items
    }
}

struct HeadersFileItem: Codable {
    let pk: String
    let shortCode: String
    let originalWidth: Int?
    let originalHeight: Int?
    let videoDuration: Double?
    let likeCount: Int
    let captionText: String?
    let commentCount: Int
    let username: String
    let userPk: String
    let userProfilePicURL: String?
    let takenAt: Int
    let sources: [String]

    enum CodingKeys: String, CodingKey {
        case pk
        case shortCode = "short_code"
        case originalWidth = "original_width"
        case originalHeight = "original_height"
        case videoDuration = "video_duration"
        case likeCount = "like_count"
        case captionText = "caption_text"
        case commentCount = "comment_count"
        case username
        case userPk = "user_pk"
        case userProfilePicURL = "user_profile_pic_url"
        case takenAt = "taken_at"
        case sources
    }
}
