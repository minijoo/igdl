import Foundation

/// Matches the pruned comments JSON the backend writes to comments.json
/// (see backend/app/instagram.py fetch_pruned_comments).
struct Comment: Codable, Identifiable {
    let id: Int
    let text: String
    let owner: String
    let likesCount: Int
    let createdAtUTC: String

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case owner
        case likesCount = "likes_count"
        case createdAtUTC = "created_at_utc"
    }
}

enum CommentsStore {
    static func load(shortCode: String) -> [Comment] {
        guard let url = try? MediaStore.commentsURL(shortCode: shortCode),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let comments = try? JSONDecoder().decode([Comment].self, from: data)
        else {
            return []
        }
        return comments
    }
}
