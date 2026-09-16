import SwiftUI
import SwiftData

@main
struct IGDLApp: App {
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestReset") {
            Self.deleteExistingStore()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: [Video.self, Category.self, Playlist.self])
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
