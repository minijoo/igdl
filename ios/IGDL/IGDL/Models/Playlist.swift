import Foundation
import SwiftData

@Model
final class Playlist {
    @Attribute(.unique) var name: String
    var isBuiltIn: Bool

    @Relationship(deleteRule: .nullify, inverse: \Video.playlists)
    var videos: [Video] = []

    init(name: String, isBuiltIn: Bool = false) {
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}
