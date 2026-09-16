import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.grid.2x2") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
    }
}
