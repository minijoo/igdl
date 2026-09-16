import SwiftUI
import SwiftData

struct DownloadView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Video> { !$0.fetched }, sort: \Video.takenAt, order: .reverse)
    private var pendingVideos: [Video]

    @State private var selected: Set<String> = [] // shortCode
    @State private var manager = DownloadManager()
    @State private var isDownloading = false

    // Split so a batch actually in progress (or that just failed) is
    // visually separated from the plain selectable list, with a real
    // per-item progress indicator instead of one perpetual, uninformative
    // spinner for the whole screen.
    private var downloadingVideos: [Video] {
        pendingVideos.filter { manager.state(for: $0.shortCode).isActiveOrFinished }
    }

    private var selectableVideos: [Video] {
        pendingVideos.filter { !manager.state(for: $0.shortCode).isActiveOrFinished }
    }

    var body: some View {
        List {
            if pendingVideos.isEmpty {
                ContentUnavailableView(
                    "Nothing to download",
                    systemImage: "checkmark.circle",
                    description: Text("Every synced video has already been downloaded.")
                )
            } else {
                if !downloadingVideos.isEmpty {
                    Section("Downloading") {
                        ForEach(downloadingVideos) { video in
                            downloadingRow(for: video)
                        }
                    }
                }
                if !selectableVideos.isEmpty {
                    Section {
                        ForEach(selectableVideos) { video in
                            selectableRow(for: video)
                        }
                    }
                }
            }
        }
        .navigationTitle("Download")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Select…") {
                    // 20 videos is roughly 20-30 minutes of typical Reels
                    // length — a reasonable single batch to queue up without
                    // the user having to hand-pick from thousands of items.
                    Button {
                        selectFromTop(count: 20)
                    } label: {
                        Label("20 from top", systemImage: "list.bullet")
                    }
                    .accessibilityIdentifier("select20FromTop")

                    Button {
                        selectRandom(count: 20)
                    } label: {
                        Label("20 random", systemImage: "shuffle")
                    }
                    .accessibilityIdentifier("select20Random")
                }
                .accessibilityIdentifier("selectMenu")
                .disabled(selectableVideos.isEmpty)
            }
        }
        .safeAreaInset(edge: .top) {
            if !pendingVideos.isEmpty {
                HStack {
                    Text("\(selected.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("selectedCount")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selectableVideos.isEmpty {
                Button {
                    startDownload()
                } label: {
                    Text(isDownloading ? "Downloading…" : "Download Selected (\(selected.count))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || isDownloading)
                .padding()
            }
        }
    }

    @ViewBuilder
    private func selectableRow(for video: Video) -> some View {
        HStack {
            Button {
                toggle(video.shortCode)
            } label: {
                Image(systemName: selected.contains(video.shortCode) ? "checkmark.square.fill" : "square")
            }
            .buttonStyle(.plain)
            .disabled(isDownloading)
            .accessibilityIdentifier("checkbox_\(video.shortCode)")

            VideoRow(video: video)
            Spacer()
            durationLabel(for: video)
        }
    }

    @ViewBuilder
    private func downloadingRow(for video: Video) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VideoRow(video: video)
                Spacer()
                durationLabel(for: video)
            }

            switch manager.state(for: video.shortCode) {
            case .notStarted:
                EmptyView()

            case .resolving:
                HStack(spacing: 6) {
                    ProgressView()
                    Text("Resolving…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            case .downloadingVideo(let progress):
                ProgressView(value: progress)
                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

            case .done:
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)

            case .failed:
                Button {
                    manager.resetState(shortCode: video.shortCode)
                } label: {
                    Label("Failed — tap to retry", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .accessibilityIdentifier("retry_\(video.shortCode)")
            }
        }
        .accessibilityIdentifier("downloadingRow_\(video.shortCode)")
    }

    /// Shows roughly how long a download might take based on video length —
    /// not the file size (which we don't know ahead of time), but duration
    /// is the best proxy the headers file gives us, and it's what the user
    /// asked to gauge downloads by.
    @ViewBuilder
    private func durationLabel(for video: Video) -> some View {
        if let formatted = video.formattedDuration {
            Text(formatted)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func toggle(_ shortCode: String) {
        if selected.contains(shortCode) {
            selected.remove(shortCode)
        } else {
            selected.insert(shortCode)
        }
    }

    /// Adds up to `count` more selections from the front of the currently
    /// displayed (most-recent-first) order, skipping anything already
    /// selected — repeatable: calling this again picks up where the last
    /// call left off, since it only ever looks at what's still unselected.
    private func selectFromTop(count: Int) {
        let unselected = selectableVideos.filter { !selected.contains($0.shortCode) }
        for video in unselected.prefix(count) {
            selected.insert(video.shortCode)
        }
    }

    /// Adds up to `count` more random selections from whatever isn't
    /// already selected — repeatable, and never re-picks an already-
    /// selected video the way a plain random sample without filtering
    /// first could.
    private func selectRandom(count: Int) {
        let unselected = selectableVideos.filter { !selected.contains($0.shortCode) }
        for video in unselected.shuffled().prefix(count) {
            selected.insert(video.shortCode)
        }
    }

    private func startDownload() {
        let shortCodes = Array(selected)
        isDownloading = true
        Task {
            await manager.downloadSelected(shortCodes: shortCodes, context: modelContext)
            isDownloading = false
            selected.removeAll()
        }
    }
}
