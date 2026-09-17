import SwiftUI
import SwiftData
import AVFoundation

@main
struct IGDLApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestReset") {
            Self.deleteExistingStore()
        }
        #endif
        // Default audio session category respects the hardware silent
        // switch, which every Reels/TikTok-style video app overrides —
        // users expect video sound to play regardless of the mute switch,
        // only actually silenced by the in-app mute button or Do Not
        // Disturb/ringer-independent system volume. .playback is the
        // standard category for this.
        try? AVAudioSession.sharedInstance().setCategory(.playback)

        // Created explicitly (rather than via the `.modelContainer(for:)`
        // scene modifier) so BackgroundDownloadCoordinator can also reach
        // it — its delegate callbacks need to write to SwiftData even when
        // no view hierarchy exists yet, e.g. the app was relaunched purely
        // to receive a background download's completion.
        let container = try! ModelContainer(for: Video.self, Category.self, Playlist.self)
        self.container = container
        BackgroundDownloadCoordinator.shared.modelContainer = container
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }

    #if DEBUG
    /// UI-test-only: gives each test run a clean SwiftData store instead of
    /// accumulating state across runs, which would make list positions
    /// (and therefore scroll-dependent element lookups) unpredictable.
    private static func deleteExistingStore() {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("default.store") {
            try? FileManager.default.removeItem(at: file)
        }
        UserDefaults.standard.removeObject(forKey: HeadersImporter.authenticatedUsernameDefaultsKey)
    }
    #endif
}
