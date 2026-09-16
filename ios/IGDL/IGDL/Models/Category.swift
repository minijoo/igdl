import Foundation
import SwiftData

@Model
final class Category {
    @Attribute(.unique) var name: String

    @Relationship(deleteRule: .nullify, inverse: \Video.category)
    var videos: [Video] = []

    init(name: String) {
        self.name = name
    }
}
