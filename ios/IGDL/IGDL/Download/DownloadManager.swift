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
/// docs/plan.md); the actual video/cover transfers are then handed off to
/// BackgroundDownloadCoordinator's background URLSession rather than done
/// directly here, so a batch keeps going even if the app is backgrounded
/// mid-download (see docs/plan.md for why a plain foreground download used
/// to just fail in that case). Resolving still runs with bounded
/// concurrency (a handful of small backend calls at a time); the CDN
/// transfers themselves are governed by the background session's own
/// scheduling, independent of this process.
///
/// SwiftData model objects aren't passed across task boundaries (not
/// Sendable) — only plain short_code strings are. All ModelContext access
/// happens back on the MainActor, where this whole class is isolated.
@Observable
@MainActor
final class DownloadManager {
    private(set) var states: [String: DownloadItemState] = [:]

    private let client: BackendClient
    private let coordinator: BackgroundDownloadCoordinator
    private let maxConcurrent = 4

    init(client: BackendClient = .shared, coordinator: BackgroundDownloadCoordinator = .shared) {
        self.client = client
        self.coordinator = coordinator
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

    /// Picks back up any downloads still running in the background session
    /// when this DownloadManager instance was (re)created — e.g. the app was
    /// relaunched after being suspended mid-batch — so the "Downloading"
    /// section reflects reality immediately instead of looking empty until
    /// the batch happens to finish on its own.
    func reconcile() async {
        for (shortCode, progress) in await coordinator.activeDownloads() {
            states[shortCode] = .downloadingVideo(progress: progress)
            coordinator.registerHandlers(
                shortCode: shortCode,
                onProgress: { [weak self] progress in
                    Task { @MainActor in self?.states[shortCode] = .downloadingVideo(progress: progress) }
                },
                onComplete: { [weak self] result in
                    Task { @MainActor in self?.apply(result, to: shortCode) }
                }
            )
        }
    }

    func downloadSelected(shortCodes: [String], context: ModelContext) async {
        for shortCode in shortCodes {
            states[shortCode] = .resolving
        }

        for chunk in shortCodes.chunked(into: maxConcurrent) {
            await withTaskGroup(of: Void.self) { group in
                for shortCode in chunk {
                    group.addTask { [weak self] in
                        await self?.startOne(shortCode: shortCode, context: context)
                    }
                }
            }
        }
    }

    private func startOne(shortCode: String, context: ModelContext) async {
        states[shortCode] = .resolving
        do {
            let resolved = try await client.resolve(shortCode: shortCode)
            try saveMetadata(resolved: resolved, context: context)

            states[shortCode] = .downloadingVideo(progress: 0)
            coordinator.enqueueDownload(
                shortCode: shortCode,
                videoURL: resolved.videoURL,
                coverURL: resolved.coverURL,
                onProgress: { [weak self] progress in
                    Task { @MainActor in self?.states[shortCode] = .downloadingVideo(progress: progress) }
                },
                onComplete: { [weak self] result in
                    Task { @MainActor in self?.apply(result, to: shortCode) }
                }
            )
        } catch {
            states[shortCode] = .failed(String(describing: error))
        }
    }

    private func apply(_ result: Result<Void, Error>, to shortCode: String) {
        switch result {
        case .success:
            states[shortCode] = .done
        case .failure(let error):
            states[shortCode] = .failed(String(describing: error))
        }
    }

    /// Saves the caption/comments half of a resolved post right away, ahead
    /// of the video/cover files actually landing — those are independent of
    /// whether the background transfer succeeds, so there's no reason to
    /// wait on it. BackgroundDownloadCoordinator flips `fetched`/
    /// `downloadedAt` itself once both files are actually on disk.
    private func saveMetadata(resolved: ResolvedPost, context: ModelContext) throws {
        let shortCode = resolved.shortCode
        let commentsData = try JSONEncoder().encode(resolved.comments)
        try MediaStore.save(commentsData, to: MediaStore.commentsURL(shortCode: shortCode))

        let descriptor = FetchDescriptor<Video>(predicate: #Predicate { $0.shortCode == shortCode })
        if let video = try? context.fetch(descriptor).first {
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
