import Foundation

/// What PlaybackView actually plays: an ordered list of videos plus a
/// starting position.
///
/// For a fixed queue (Library, Home's Recently Added, Playlists, Categories,
/// Creators) `videos` never changes after creation. For "Shuffle All" (see
/// HomeView) it grows on demand as playback advances, via `ensureBuffer` —
/// PlaybackView reads `videos` fresh on every render since this class is
/// @Observable, so appending here is picked up automatically without
/// PlaybackView needing to know it's playing a dynamic queue at all.
@Observable
final class PlaybackQueue: Identifiable {
    let id = UUID()
    private(set) var videos: [Video]
    let startIndex: Int

    /// Remaining not-yet-dealt-out videos for a dynamic (shuffle) queue, in
    /// their already-shuffled order, plus how far into it we've drawn.
    /// Dealing sequentially from one upfront shuffle of the whole pool —
    /// rather than repeatedly picking a random not-yet-seen video on demand —
    /// is what naturally guarantees "never repeats what's already queued or
    /// played," with no extra bookkeeping needed.
    private var reserve: [Video] = []
    private var reserveIndex = 0

    init(videos: [Video], startIndex: Int) {
        self.videos = videos
        self.startIndex = startIndex
    }

    /// Shuffle-all: deals out `initialCount` videos to start playing
    /// immediately, keeping the rest of the shuffled pool in reserve to grow
    /// into as playback advances (see `ensureBuffer`).
    convenience init(shuffling pool: [Video], initialCount: Int = 5) {
        let shuffled = pool.shuffled()
        self.init(videos: Array(shuffled.prefix(initialCount)), startIndex: 0)
        reserve = shuffled
        reserveIndex = videos.count
    }

    /// Called as playback advances — tops the queue back up from the reserve
    /// so there's always `lookahead` more videos already loaded beyond the
    /// current position. A no-op once the reserve (and therefore the whole
    /// library) is exhausted, or for a fixed queue, which never had a reserve
    /// to begin with.
    func ensureBuffer(current index: Int, lookahead: Int = 3) {
        while videos.count - 1 - index <= lookahead, reserveIndex < reserve.count {
            videos.append(reserve[reserveIndex])
            reserveIndex += 1
        }
    }
}

extension Array where Element == Video {
    /// Turns this list into a playback queue starting at `video` — see
    /// PlaybackQueue. Only downloaded videos can actually play, so the
    /// source list is filtered to `fetched` first — an undownloaded video
    /// in between two downloaded ones is simply skipped when paging.
    func playableQueue(startingAt video: Video) -> PlaybackQueue? {
        let playable = filter(\.fetched)
        guard let index = playable.firstIndex(where: { $0.pk == video.pk }) else { return nil }
        return PlaybackQueue(videos: playable, startIndex: index)
    }
}
