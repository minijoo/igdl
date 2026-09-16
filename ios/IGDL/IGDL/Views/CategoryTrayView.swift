import SwiftUI
import SwiftData

/// The tray opened from the playback screen's categorize button. Assigning
/// or creating a category both happen only here — this is the one place
/// the category list is ever mutated from; removing a video from a
/// category happens instead from the Library's category view (see
/// CategoriesListView), never here.
struct CategoryTrayView: View {
    let video: Video

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // Most-recently-used first — the whole point of tracking lastUsedAt is
    // so the categories you're actively sorting into stay at the top
    // instead of requiring a scroll through an alphabetical list every time.
    @Query(sort: \Category.lastUsedAt, order: .reverse) private var categories: [Category]

    @State private var isAddingCategory = false
    @State private var newCategoryName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(categories) { category in
                    categoryRow(name: category.name, isSelected: video.category == category) {
                        select(category)
                    }
                }

                // Always last, regardless of recency — this is "no
                // category," not a category itself, so it doesn't compete
                // for the most-recently-used ordering above it.
                categoryRow(name: "None", isSelected: video.category == nil) {
                    selectNone()
                }
            }
            .navigationTitle("Categorize")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        isAddingCategory = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityIdentifier("addCategoryButton")
                    Spacer()
                }
                .padding()
                .background(.bar)
            }
            .alert("New Category", isPresented: $isAddingCategory) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
                Button("Add") { addCategory() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func categoryRow(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityIdentifier("categoryRow_\(name)")
    }

    private func select(_ category: Category) {
        video.category = category
        category.lastUsedAt = .now
        try? modelContext.save()
        dismiss()
    }

    private func selectNone() {
        video.category = nil
        try? modelContext.save()
        dismiss()
    }

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        newCategoryName = ""
        guard !name.isEmpty else { return }

        // Reuse an existing category with this name rather than risking a
        // duplicate-name insert against Category.name's unique constraint.
        if let existing = categories.first(where: { $0.name == name }) {
            select(existing)
            return
        }

        let category = Category(name: name)
        modelContext.insert(category)
        select(category)
    }
}
