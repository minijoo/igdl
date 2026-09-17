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
            let message = Self.describe(error)
            // Printed via NSLog (not print — see docs/plan.md, print() from
            // the app under test doesn't reach xcodebuild's piped stdout,
            // and this is the same "actually visible in the device console"
            // concern for real on-device debugging) so a resolve failure has
            // a client-side trace even when nothing reached the backend's
            // own logs at all (e.g. a request cancelled while still queued
            // behind the backend's resolve lock).
            NSLog("[IGDL] resolve failed shortCode=%@ error=%@", shortCode, message)
            markIncompatibleIfNeeded(shortCode: shortCode, message: message, context: context)
            states[shortCode] = .failed(message)
        }
    }

    private func apply(_ result: Result<Void, Error>, to shortCode: String) {
        switch result {
        case .success:
            states[shortCode] = .done
        case .failure(let error):
            let message = Self.describe(error)
            NSLog("[IGDL] download failed shortCode=%@ error=%@", shortCode, message)
            states[shortCode] = .failed(message)
        }
    }

    /// A short, human-readable reason — shown in the UI (see DownloadView's
    /// failed row) and logged, rather than a raw `String(describing:)` dump
    /// (which for a URLError includes a whole NSError UserInfo blob).
    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "Timed out"
            case .notConnectedToInternet, .networkConnectionLost: return "No network connection"
            case .cancelled: return "Cancelled"
            default: return urlError.localizedDescription
            }
        }
        if case .badStatusCode(let code, let message)? = error as? BackendClientError {
            return message ?? "Server returned \(code)"
        }
        return String(describing: error)
    }

    /// "post has no video" is the backend's exact wording (see
    /// backend/app/instagram.py) for a slideshow/carousel post — a
    /// permanent, not-network-related failure, not something a retry could
    /// ever fix. Flagging it here means the Download screen can file it
    /// under "Not Reels" from now on instead of leaving it to fail the same
    /// way every time it's selected again.
    private static let notReelsErrorMessage = "post has no video"

    private func markIncompatibleIfNeeded(shortCode: String, message: String, context: ModelContext) {
        guard message == Self.notReelsErrorMessage else { return }
        let descriptor = FetchDescriptor<Video>(predicate: #Predicate { $0.shortCode == shortCode })
        if let video = try? context.fetch(descriptor).first {
            video.isVideo = false
            try? context.save()
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
