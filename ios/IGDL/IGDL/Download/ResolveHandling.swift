import Foundation
import SwiftData

/// What happens to SwiftData once a resolve (see BackgroundDownloadCoordinator)
/// comes back, success or failure. Pulled out into plain functions taking
/// an explicit ModelContext — not methods on the coordinator — so this can
/// be unit tested directly against an in-memory context, without needing
/// to simulate an actual background URLSession delegate callback (which
/// isn't realistically mockable; background transfers run in a separate
/// system process, not this one).
enum ResolveHandling {
    /// The backend's exact wording (see backend/app/instagram.py) for a
    /// slideshow/carousel post — a permanent, not-network-related failure,
    /// not something a retry could ever fix.
    static let notReelsErrorMessage = "post has no video"

    /// Saves the caption/comments half of a resolved post right away, ahead
    /// of the video/cover files actually landing — those are independent of
    /// whether the background transfer succeeds, so there's no reason to
    /// wait on it. BackgroundDownloadCoordinator flips `fetched`/
    /// `downloadedAt` itself once both files are actually on disk.
    static func saveMetadata(resolved: ResolvedPost, context: ModelContext) throws {
        let shortCode = resolved.shortCode
        let commentsData = try JSONEncoder().encode(resolved.comments)
        try MediaStore.save(commentsData, to: MediaStore.commentsURL(shortCode: shortCode))

        let descriptor = FetchDescriptor<Video>(predicate: #Predicate { $0.shortCode == shortCode })
        if let video = try? context.fetch(descriptor).first {
            // The backend's caption is freshly scraped, so it's the latest
            // version — worth refreshing over whatever the headers file
            // snapshot had, but only if we actually got one.
            let trimmedCaption = resolved.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedCaption.isEmpty {
                video.captionText = trimmedCaption
            }
            try? context.save()
        }
    }

    /// Flags a video as not actually a Reel (see docs/plan.md's
    /// "Incompatible videos" item) so the Download screen can file it under
    /// "Not Reels" from now on instead of leaving it to fail the same way
    /// every time it's reselected.
    static func markIncompatibleIfNeeded(shortCode: String, message: String?, context: ModelContext) {
        guard message == notReelsErrorMessage else { return }
        let descriptor = FetchDescriptor<Video>(predicate: #Predicate { $0.shortCode == shortCode })
        if let video = try? context.fetch(descriptor).first {
            video.isVideo = false
            try? context.save()
        }
    }
}
