import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SyncView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingPicker = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Import Headers File…") {
                        showingPicker = true
                    }
                } footer: {
                    Text("Pick the headers.json produced by the Retriever script. Re-importing is safe — existing videos are updated in place, not duplicated.")
                }

                #if DEBUG
                Section {
                    Button("Load repo headers.json (DEBUG)") {
                        loadDebugHeadersFile()
                    }
                    Button("Seed local fixture videos (DEBUG)") {
                        seedFixtureVideos()
                    }
                } footer: {
                    Text("Simulator-only dev shortcuts — read directly from the host filesystem. Seeding copies pre-downloaded video/cover/comments into MediaStore and marks matching videos fetched, without any network call.")
                }
                #endif

                if let resultMessage {
                    Section {
                        Text(resultMessage)
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Sync")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingPicker,
                allowedContentTypes: [.json]
            ) { result in
                handlePickerResult(result)
            }
        }
    }

    private func handlePickerResult(_ result: Result<URL, Error>) {
        errorMessage = nil
        resultMessage = nil
        do {
            let url = try result.get()
            let count = try HeadersImporter.importFile(at: url, context: modelContext)
            resultMessage = "Imported \(count) items."
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    #if DEBUG
    private func loadDebugHeadersFile() {
        errorMessage = nil
        resultMessage = nil
        do {
            let path = ProcessInfo.processInfo.environment["IGDL_TEST_HEADERS_PATH"]
                ?? "/Users/jordy/workspace/igdl/headers.json"
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            let count = try HeadersImporter.importData(data, context: modelContext)
            resultMessage = "Imported \(count) items."
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    /// Scans a fixtures directory (env-var overridable, used by UI tests) of
    /// `<shortcode>/{video.mp4,cover.jpg,comments.json}` folders, and for any
    /// shortcode that matches an already-imported Video, copies those files
    /// into MediaStore and marks it fetched — a way to exercise
    /// playback-screen UI (aspect ratio, controls, comments) against real
    /// downloaded media without going through the network/backend at all.
    private func seedFixtureVideos() {
        errorMessage = nil
        resultMessage = nil
        let root = ProcessInfo.processInfo.environment["IGDL_TEST_FIXTURES_PATH"]
            ?? "/Users/jordy/workspace/igdl/ios/test_fixtures"
        let rootURL = URL(fileURLWithPath: root)

        guard let shortCodes = try? FileManager.default.contentsOfDirectory(atPath: root) else {
            errorMessage = "No fixtures found at \(root)"
            return
        }

        var seeded = 0
        for shortCode in shortCodes {
            let descriptor = FetchDescriptor<Video>(predicate: #Predicate<Video> { $0.shortCode == shortCode })
            guard let video = try? modelContext.fetch(descriptor).first else { continue }

            let fixtureDir = rootURL.appendingPathComponent(shortCode)
            do {
                if let videoURL = try? MediaStore.videoURL(shortCode: shortCode) {
                    try Data(contentsOf: fixtureDir.appendingPathComponent("video.mp4")).write(to: videoURL)
                }
                if let coverURL = try? MediaStore.coverURL(shortCode: shortCode) {
                    try Data(contentsOf: fixtureDir.appendingPathComponent("cover.jpg")).write(to: coverURL)
                }
                if let commentsURL = try? MediaStore.commentsURL(shortCode: shortCode) {
                    try Data(contentsOf: fixtureDir.appendingPathComponent("comments.json")).write(to: commentsURL)
                }
                video.fetched = true
                seeded += 1
            } catch {
                continue
            }
        }
        try? modelContext.save()
        resultMessage = "Seeded \(seeded) fixture video(s)."
    }
    #endif
}
