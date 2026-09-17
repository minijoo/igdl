import UIKit

/// Only exists to receive one UIKit-only callback SwiftUI has no native
/// equivalent for: iOS relaunches/wakes the app in the background to deliver
/// completed transfers from BackgroundDownloadCoordinator's URLSession, and
/// this is how that handoff arrives.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundDownloadCoordinator.sessionIdentifier else {
            completionHandler()
            return
        }
        // Call this back once urlSessionDidFinishEvents(forBackgroundURLSession:)
        // confirms every queued delegate callback for this session has run —
        // reconnecting right away (rather than waiting for some SwiftUI view
        // to eventually touch the session) so those callbacks are actually
        // delivered promptly instead of sitting queued.
        BackgroundDownloadCoordinator.shared.backgroundSessionCompletionHandler = completionHandler
        BackgroundDownloadCoordinator.shared.reconnectIfNeeded()
    }
}
