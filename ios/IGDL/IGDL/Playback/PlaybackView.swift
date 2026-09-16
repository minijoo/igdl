import SwiftUI
import AVFoundation
import SwiftData

/// Vertical Reels-style pager. Only the current page ± 1 get a live
/// AVPlayer — with potentially thousands of videos in a playlist, one
/// AVPlayer per item isn't viable, and ±1 keeps the adjacent video ready to
/// play immediately on swipe release rather than loading fresh at that
/// moment.
struct PlaybackView: View {
    let videos: [Video]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var scrollPosition: Int?
    @State private var players: [Int: AVPlayer] = [:]
    @State private var loopObservers: [Int: NSObjectProtocol] = [:]
    // Not local @State inside PlaybackPageView — see PlaybackCoordinator
    // (which is why *this whole view* is now presented from RootTabView
    // instead of per-row) for the bug that caused.
    @State private var categorizingVideo: Video?

    var body: some View {
        // A ZStack that itself respects the safe area, with only the video
        // content inside ignoring it, so the dismiss button naturally sits
        // right at the safe area's top edge (as high as possible while
        // still fully visible/tappable) instead of a guessed padding value.
        ZStack(alignment: .topLeading) {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(videos.enumerated()), id: \.offset) { index, video in
                        PlaybackPageView(
                            video: video,
                            player: players[index],
                            isActive: index == scrollPosition,
                            onCategorize: { categorizingVideo = video }
                        )
                        .containerRelativeFrame(.vertical)
                        // Identity is the video's own stable persistent id,
                        // not its array position — see docs/plan.md for why:
                        // index-based identity meant any upstream re-render
                        // that rebuilt `videos` (even with the exact same
                        // videos) could make SwiftUI treat "index 2" as a
                        // brand new page instead of recognizing it as the
                        // same video that was already there, tearing down
                        // and recreating every page's @State (silently
                        // closing anything presented from it, like the
                        // category tray).
                        .id(video.persistentModelID)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollPosition)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()

            Button { dismiss() } label: {
                Image(systemName: "chevron.backward")
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .accessibilityIdentifier("playbackDismiss")
            // Exposes the pager's actual scroll position directly, for UI
            // tests to check whether a swipe really changed pages without
            // depending on child-view accessibility-identifier propagation
            // timing (which showed lag/ambiguity when diagnosing a swipe
            // regression).
            .accessibilityValue("scrollPosition_\(scrollPosition ?? -1)")
            .padding(8)
        }
        .background(Color.black)
        .sheet(item: $categorizingVideo) { video in
            CategoryTrayView(video: video)
        }
        // Swipe right to dismiss, like iOS's edge-swipe-back — a horizontal
        // gesture, so it doesn't fight the vertical paging gesture.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.width > 80 && abs(value.translation.height) < 50 {
                        dismiss()
                    }
                }
        )
        .onAppear {
            scrollPosition = startIndex
            updatePlayers(around: startIndex)
        }
        .onChange(of: scrollPosition) { _, newValue in
            guard let newValue else { return }
            updatePlayers(around: newValue)
        }
        .onDisappear {
            for (_, token) in loopObservers { NotificationCenter.default.removeObserver(token) }
            for (_, player) in players { player.pause() }
            players.removeAll()
            loopObservers.removeAll()
        }
    }

    private func updatePlayers(around index: Int) {
        let keep = Set([index - 1, index, index + 1]).filter { videos.indices.contains($0) }

        for key in players.keys where !keep.contains(key) {
            players[key]?.pause()
            if let token = loopObservers[key] {
                NotificationCenter.default.removeObserver(token)
                loopObservers.removeValue(forKey: key)
            }
            players.removeValue(forKey: key)
        }

        for i in keep where players[i] == nil {
            guard let url = try? MediaStore.videoURL(shortCode: videos[i].shortCode) else { continue }
            let player = AVPlayer(url: url)
            players[i] = player
            loopObservers[i] = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                player.play()
            }
        }

        players[index]?.seek(to: .zero)
        players[index]?.play()
        for (key, player) in players where key != index {
            player.pause()
        }
    }
}
