import Foundation
import SwiftData
import Observation

enum DownloadItemState: Equatable {
    case notStarted
    case resolving // asking the backend for CDN URLs + comments
    case downloadingVideo(progress: Double) // 0...1
    case done
    case failed(String)

    /// Whether this item belongs in DownloadView's "Downloading" section —
    /// i.e. it's been touched at all, as opposed to still sitting in the
    /// plain selectable list untouched.
    var isActiveOrFinished: Bool {
        if case .notStarted = self { return false }
        return true
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

/// Orchestrates downloading selected videos. The backend resolves a post to
/// its CDN video/cover URLs, caption, and top comments in one call (see
/// docs/plan.md) — this class then downloads the video/cover directly from
/// Instagram's CDN itself and saves everything via MediaStore. Runs with
/// bounded concurrency rather than fully sequential or fully parallel:
/// resolving still goes through the backend's single-Instagram-call-at-a-
/// time lock, but the CDN downloads themselves are fine in parallel since
/// they don't touch Instagram's authenticated API at all.
///
/// SwiftData model objects aren't passed across task boundaries (not
/// Sendable) — only plain short_code strings are. All ModelContext access
/// happens back on the MainActor, where this whole class is isolated.
@Observable
@MainActor
final class DownloadManager {
    private(set) var states: [String: DownloadItemState] = [:]

    private let client: BackendClient
    private let maxConcurrent = 4

    init(client: BackendClient = .shared) {
        self.client = client
    }

    func state(for shortCode: String) -> DownloadItemState {
        states[shortCode] ?? .notStarted
    }

    /// Moves a failed item back to the plain selectable list so the user can
    /// retry it — otherwise a permanent failure would sit in the
    /// "Downloading" section forever with no way back.
    func resetState(shortCode: String) {
        states.removeValue(forKey: shortCode)
    }

    func downloadSelected(shortCodes: [String], context: ModelContext) async {
        for shortCode in shortCodes {
            states[shortCode] = .resolving
        }

        for chunk in shortCodes.chunked(into: maxConcurrent) {
            await withTaskGroup(of: Void.self) { group in
                for shortCode in chunk {
                    group.addTask { [weak self] in
                        await self?.downloadOne(shortCode: shortCode, context: context)
                    }
                }
            }
        }
    }

    private func downloadOne(shortCode: String, context: ModelContext) async {
        states[shortCode] = .resolving
        do {
            let resolved = try await client.resolve(shortCode: shortCode)

            states[shortCode] = .downloadingVideo(progress: 0)
            let videoData = try await client.download(url: resolved.videoURL) { [weak self] progress in
                guard let self else { return }
                Task { @MainActor in
                    self.states[shortCode] = .downloadingVideo(progress: progress)
                }
            }
            let coverData = try await client.download(url: resolved.coverURL)

            try save(resolved: resolved, videoData: videoData, coverData: coverData, context: context)

            states[shortCode] = .done
        } catch {
            states[shortCode] = .failed(String(describing: error))
        }
    }

    private func save(resolved: ResolvedPost, videoData: Data, coverData: Data, context: ModelContext) throws {
        let shortCode = resolved.shortCode
        try MediaStore.save(videoData, to: MediaStore.videoURL(shortCode: shortCode))
        try MediaStore.save(coverData, to: MediaStore.coverURL(shortCode: shortCode))
        let commentsData = try JSONEncoder().encode(resolved.comments)
        try MediaStore.save(commentsData, to: MediaStore.commentsURL(shortCode: shortCode))

        let descriptor = FetchDescriptor<Video>(predicate: #Predicate { $0.shortCode == shortCode })
        if let video = try? context.fetch(descriptor).first {
            video.fetched = true
            video.downloadedAt = .now
            // The backend's caption is freshly scraped, so it's the latest
            // version — worth refreshing over whatever the headers file
            // snapshot had, but only if we actually got one.
            let trimmedCaption = resolved.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedCaption.isEmpty {
                video.captionText = trimmedCaption
            }
            try? context.save()
        }
    }
}
