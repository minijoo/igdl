import SwiftUI

struct RootTabView: View {
    @State private var coordinator = PlaybackCoordinator()

    var body: some View {
        // Redeclaring as @Bindable to get a binding out of an @Observable
        // held in @State — the standard iOS 17+ pattern for this.
        @Bindable var coordinator = coordinator

        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.grid.2x2") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .environment(coordinator)
        // Presented once, here — see PlaybackCoordinator for why this can't
        // live per-row inside each list anymore.
        .fullScreenCover(item: $coordinator.playback) { list in
            PlaybackView(videos: list.videos, startIndex: list.startIndex)
        }
    }
}
