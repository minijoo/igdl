import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Playlists") { PlaylistsListView() }
                NavigationLink("Creators") { CreatorsListView() }
                NavigationLink("Videos") { AllVideosListView() }
                NavigationLink("Categories") { CategoriesListView() }
            }
            .navigationTitle("Library")
        }
    }
}
