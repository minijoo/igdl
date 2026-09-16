import SwiftUI
import SwiftData

struct CategoriesListView: View {
    @Query(sort: \Category.name) private var categories: [Category]

    var body: some View {
        List {
            if categories.isEmpty {
                ContentUnavailableView(
                    "No categories yet",
                    systemImage: "tag",
                    description: Text("Category assignment isn't built yet — videos have no category until then.")
                )
            } else {
                ForEach(categories) { category in
                    NavigationLink {
                        CategoryDetailView(category: category)
                    } label: {
                        HStack {
                            Text(category.name)
                            Spacer()
                            Text("\(category.videos.filter(\.fetched).count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Categories")
    }
}

struct CategoryDetailView: View {
    let category: Category

    private var sortedVideos: [Video] {
        category.videos.filter(\.fetched).sorted(by: { $0.takenAt > $1.takenAt })
    }

    var body: some View {
        List {
            ForEach(sortedVideos) { video in
                PlayableVideoRow(video: video, allVideos: sortedVideos)
            }
        }
        .navigationTitle(category.name)
    }
}
