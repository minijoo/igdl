import Foundation

/// Single shared source of truth for "what's currently playing," held at
/// RootTabView and read by every PlayableVideoRow via the environment.
///
/// This replaces each row owning its own local `@State` + `.fullScreenCover`
/// — that per-row approach had a real bug: presenting a `.sheet` (the
/// category tray) from within a `.fullScreenCover` whose presenting row was
/// a *direct child of a NavigationStack's root* (Home's Recently Added)
/// caused the fullScreenCover's content to be torn down and recreated
/// shortly after, silently closing the tray. The same fullScreenCover
/// triggered from a *pushed* view (Library → Videos) never showed this.
/// Presenting from one stable, top-level location instead of per-row
/// removes that root-vs-pushed asymmetry entirely, regardless of which
/// list originally launched playback.
@Observable
final class PlaybackCoordinator {
    var playback: PlaybackQueue?

    func play(_ queue: PlaybackQueue?) {
        playback = queue
    }
}
