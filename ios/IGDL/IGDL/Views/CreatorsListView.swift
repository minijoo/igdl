import SwiftUI
import SwiftData

struct CreatorsListView: View {
    @Query(filter: #Predicate<Video> { $0.fetched }) private var allVideos: [Video]

    private var creators: [(username: String, count: Int)] {
        Dictionary(grouping: allVideos, by: { $0.username })
            .map { (username: $0.key, count: $0.value.count) }
            .sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }

    var body: some View {
        List(creators, id: \.username) { creator in
            NavigationLink {
                CreatorDetailView(username: creator.username)
            } label: {
                HStack {
                    Text(creator.username)
                    Spacer()
                    Text("\(creator.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Creators")
    }
}

struct CreatorDetailView: View {
    let username: String
    @Query(filter: #Predicate<Video> { $0.fetched }) private var allVideos: [Video]

    private var videos: [Video] {
        allVideos
            .filter { $0.username == username }
            .sorted { $0.takenAt > $1.takenAt }
    }

    var body: some View {
        List(videos) { video in
            PlayableVideoRow(video: video, allVideos: videos)
        }
        .navigationTitle(username)
    }
}
