import SwiftUI
import SwiftData

struct AllVideosListView: View {
    // Undownloaded videos have only header data (username/caption/counts) —
    // not enough to help organize or watch anything, so Library only shows
    // what's actually been fetched. DownloadView is the screen for
    // everything still pending.
    @Query(filter: #Predicate<Video> { $0.fetched }, sort: \Video.takenAt, order: .reverse)
    private var videos: [Video]

    var body: some View {
        List(videos) { video in
            PlayableVideoRow(video: video, allVideos: videos)
        }
        .navigationTitle("Videos (\(videos.count))")
    }
}

struct PlaylistsListView: View {
    @Query(sort: \Playlist.name) private var playlists: [Playlist]

    var body: some View {
        List(playlists) { playlist in
            NavigationLink {
                PlaylistDetailView(playlist: playlist)
            } label: {
                HStack {
                    Text(playlist.name)
                    Spacer()
                    Text("\(playlist.videos.filter(\.fetched).count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Playlists")
    }
}
