import SwiftUI
import SwiftData

struct SearchView: View {
    @Query(sort: \Video.takenAt, order: .reverse) private var allVideos: [Video]
    @State private var query = ""

    private var results: [Video] {
        guard !query.isEmpty else { return [] }
        return allVideos.filter {
            $0.username.localizedCaseInsensitiveContains(query)
                || ($0.captionText?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List(results) { video in
                VideoRow(video: video)
            }
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .navigationTitle("Search")
        }
        .searchable(text: $query, prompt: "Username or caption")
    }
}
