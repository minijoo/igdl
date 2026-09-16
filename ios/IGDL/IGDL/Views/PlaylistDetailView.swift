import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist

    private var sortedVideos: [Video] {
        playlist.videos.filter(\.fetched).sorted(by: { $0.takenAt > $1.takenAt })
    }

    var body: some View {
        List {
            ForEach(sortedVideos) { video in
                PlayableVideoRow(video: video, allVideos: sortedVideos)
            }
        }
        .navigationTitle(playlist.name)
    }
}
