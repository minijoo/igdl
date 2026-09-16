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
                    description: Text("Categorize a video from its playback screen to create one.")
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

/// Removing a video here only ever nullifies `video.category` — the
/// category itself is never deleted from here, only from the tray (see
/// CategoryTrayView), and its count updates for free since it's just
/// `category.videos.count` via the relationship, not a separately
/// maintained field.
struct CategoryDetailView: View {
    let category: Category

    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode
    @State private var selection = Set<PersistentIdentifier>()

    private var sortedVideos: [Video] {
        category.videos.filter(\.fetched).sorted(by: { $0.takenAt > $1.takenAt })
    }

    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing ?? false
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(sortedVideos) { video in
                PlayableVideoRow(video: video, allVideos: sortedVideos)
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            remove([video])
                        }
                        .accessibilityIdentifier("removeFromCategory_\(video.shortCode)")
                    }
            }
        }
        .navigationTitle(category.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            if isEditing && !selection.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button("Remove Selected (\(selection.count))", role: .destructive) {
                        removeSelected()
                    }
                    .accessibilityIdentifier("removeSelectedFromCategory")
                }
            }
        }
    }

    private func remove(_ videos: [Video]) {
        for video in videos {
            video.category = nil
        }
        try? modelContext.save()
    }

    private func removeSelected() {
        let toRemove = sortedVideos.filter { selection.contains($0.persistentModelID) }
        remove(toRemove)
        selection.removeAll()
    }
}
