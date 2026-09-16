import Foundation

struct PlayableList: Identifiable {
    let id = UUID()
    let videos: [Video]
    let startIndex: Int
}

extension Array where Element == Video {
    /// Turns this list into a playlist starting at `video`, per the Playback
    /// screen behavior in docs/plan.md: "the list of videos ... is turned
    /// into a playlist, and the position of that video in that list is sent
    /// to the screen." Only downloaded videos can actually play, so the
    /// source list is filtered to `fetched` first — an undownloaded video
    /// in between two downloaded ones is simply skipped when paging.
    func playableList(startingAt video: Video) -> PlayableList? {
        let playable = filter(\.fetched)
        guard let index = playable.firstIndex(where: { $0.pk == video.pk }) else { return nil }
        return PlayableList(videos: playable, startIndex: index)
    }
}
