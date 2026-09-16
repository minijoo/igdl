import Foundation
import SwiftData

@Model
final class Category {
    @Attribute(.unique) var name: String
    // Drives ordering in the category tray (see CategoryTrayView) — bumped
    // whenever this category is created or assigned to a video. Declared
    // with an inline default (not just an initializer default) so SwiftData's
    // lightweight migration can backfill it for any row that predates this
    // field.
    var lastUsedAt: Date = Date.now

    // Video count is intentionally not a separate stored field — `videos`
    // is already the source of truth via the relationship, so `.count`
    // can never drift out of sync with reality the way a manually
    // maintained counter could (e.g. if a removal path forgot to
    // decrement it).
    @Relationship(deleteRule: .nullify, inverse: \Video.category)
    var videos: [Video] = []

    init(name: String, lastUsedAt: Date = .now) {
        self.name = name
        self.lastUsedAt = lastUsedAt
    }
}
