import SwiftUI

/// Wraps VideoRow with tap-to-play, turning `allVideos` (the list this row
/// is shown in) into a playlist starting at `video`, per the Playback
/// screen behavior in docs/plan.md. Every caller now filters to `fetched`
/// videos before reaching this row (Library/Home only show downloaded
/// videos), but the guard stays as cheap insurance against a future caller
/// forgetting to — there's nothing local to play for an undownloaded video.
///
/// Playback itself is presented from RootTabView via PlaybackCoordinator,
/// not from a `.fullScreenCover` here — see PlaybackCoordinator for why.
struct PlayableVideoRow: View {
    let video: Video
    let allVideos: [Video]

    @Environment(PlaybackCoordinator.self) private var coordinator

    var body: some View {
        VideoRow(video: video)
            .contentShape(Rectangle())
            .accessibilityIdentifier("videoRow_\(video.shortCode)")
            .onTapGesture {
                guard video.fetched else { return }
                coordinator.play(allVideos.playableList(startingAt: video))
            }
    }
}
