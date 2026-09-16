import SwiftUI
import SwiftData

struct HomeView: View {
    // "Recently Added" means most recently *downloaded*, not most recently
    // posted/liked on Instagram — sorted by downloadedAt, not takenAt
    // (contrast with Library's "Videos" list, which intentionally keeps
    // takenAt — see docs/plan.md and Video.downloadedAt).
    @Query(filter: #Predicate<Video> { $0.fetched }, sort: \Video.downloadedAt, order: .reverse)
    private var fetchedVideos: [Video]
    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @Query(filter: #Predicate<Video> { !$0.fetched }) private var pendingVideos: [Video]

    @State private var showingSync = false

    private var recentlyAdded: [Video] {
        Array(fetchedVideos.prefix(6))
    }

    var body: some View {
        NavigationStack {
            List {
                if !pendingVideos.isEmpty {
                    NavigationLink {
                        DownloadView()
                    } label: {
                        Label("Download New Videos (\(pendingVideos.count))", systemImage: "arrow.down.circle")
                    }
                }

                if !recentlyAdded.isEmpty {
                    Section("Recently Added") {
                        ForEach(recentlyAdded) { video in
                            PlayableVideoRow(video: video, allVideos: fetchedVideos)
                        }
                    }
                }

                if !playlists.isEmpty {
                    Section("Playlists") {
                        ForEach(playlists) { playlist in
                            NavigationLink(playlist.name) {
                                PlaylistDetailView(playlist: playlist)
                            }
                        }
                    }
                }

                if fetchedVideos.isEmpty {
                    ContentUnavailableView(
                        "No videos yet",
                        systemImage: "tray",
                        description: Text(
                            pendingVideos.isEmpty
                                ? "Import a headers file from Settings to get started."
                                : "You have \(pendingVideos.count) videos waiting to download."
                        )
                    )
                }
            }
            .navigationTitle("IGDL")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings") { showingSync = true }
                }
            }
            .sheet(isPresented: $showingSync) {
                SyncView()
            }
        }
    }
}
