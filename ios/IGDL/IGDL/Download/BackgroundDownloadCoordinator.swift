import Foundation
import SwiftData

/// Downloads a resolved post's video + cover files using a background
/// URLSession, so a batch keeps transferring even after the app is
/// backgrounded. A plain foreground URLSession task gets killed within
/// seconds of the app being suspended — that's why downloads used to show up
/// as "failed" just from switching away from the app mid-batch. A background
/// URLSessionConfiguration hands the transfer off to a system daemon
/// (nsurlsessiond) that keeps running independently of this process,
/// including across the process being suspended or terminated by the OS
/// (not a user-initiated force-quit, which still cancels everything).
///
/// A singleton, not per-screen state: the delegate has to exist and be
/// reachable the moment iOS relaunches the app in the background to deliver
/// a completed transfer, which can happen before any SwiftUI view (and
/// therefore before any DownloadManager) exists.
final class BackgroundDownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = BackgroundDownloadCoordinator()
    static let sessionIdentifier = "com.jordy.igdl.background-downloads"

    /// Set once from IGDLApp at launch. Needed here directly (not just handed
    /// down via SwiftUI's environment) because delegate callbacks can fire
    /// with no view hierarchy around to hand a ModelContext down from.
    var modelContainer: ModelContainer?

    /// Stashed by AppDelegate until this background session's queued
    /// delegate callbacks have all been delivered, per Apple's documented
    /// background-transfer completion handshake.
    var backgroundSessionCompletionHandler: (() -> Void)?

    private enum AssetKind: String { case video, cover }

    /// Per-shortCode callbacks, live only while a DownloadManager is around
    /// to receive them — safe to be missing (background relaunch with no UI
    /// up yet, or simply not re-registered after a fresh launch) since a
    /// finished transfer's actual result (the file on disk, the SwiftData
    /// flip to fetched=true) never depends on these being registered.
    private var progressHandlers: [String: (Double) -> Void] = [:]
    private var completionHandlers: [String: (Result<Void, Error>) -> Void] = [:]
    private let handlersLock = NSLock()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() { super.init() }

    /// Forces the background session to exist/reconnect — called from
    /// AppDelegate as soon as iOS wakes the app for this session's events,
    /// rather than waiting for whatever SwiftUI view happens to touch it
    /// first, so queued delegate callbacks get delivered promptly.
    func reconnectIfNeeded() {
        _ = session
    }

    /// Kicks off the video and cover downloads unconditionally (a plain
    /// redownload-both approach rather than tracking which single asset
    /// survived a prior partial failure — simpler, and the cost of
    /// occasionally re-fetching one already-good file is negligible next to
    /// the batch sizes here).
    func enqueueDownload(
        shortCode: String,
        videoURL: URL,
        coverURL: URL,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        registerHandlers(shortCode: shortCode, onProgress: onProgress, onComplete: onComplete)
        start(url: videoURL, shortCode: shortCode, kind: .video)
        start(url: coverURL, shortCode: shortCode, kind: .cover)
    }

    func registerHandlers(
        shortCode: String,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        handlersLock.lock()
        progressHandlers[shortCode] = onProgress
        completionHandlers[shortCode] = onComplete
        handlersLock.unlock()
    }

    /// Recovers shortCodes with a still-running transfer directly from the
    /// background session's own task list — used on (re)launch to repaint
    /// the "Downloading" section for transfers that outlived the previous
    /// process, instead of it looking empty until the next download.
    func activeDownloads() async -> [String: Double] {
        var progressByShortCode: [String: Double] = [:]
        for task in await session.allTasks {
            guard let (shortCode, kind) = Self.parse(taskDescription: task.taskDescription) else { continue }
            switch kind {
            case .video:
                let expected = task.countOfBytesExpectedToReceive
                progressByShortCode[shortCode] = expected > 0 ? Double(task.countOfBytesReceived) / Double(expected) : 0
            case .cover:
                // Only the video leg reports visible progress (matches prior
                // behavior); if only its cover task is left, the video side
                // is already done.
                if progressByShortCode[shortCode] == nil { progressByShortCode[shortCode] = 1 }
            }
        }
        return progressByShortCode
    }

    private func start(url: URL, shortCode: String, kind: AssetKind) {
        let task = session.downloadTask(with: url)
        task.taskDescription = "\(shortCode)|\(kind.rawValue)"
        task.resume()
    }

    private static func parse(taskDescription: String?) -> (shortCode: String, kind: AssetKind)? {
        guard let taskDescription, let separator = taskDescription.lastIndex(of: "|") else { return nil }
        let shortCode = String(taskDescription[..<separator])
        guard let kind = AssetKind(rawValue: String(taskDescription[taskDescription.index(after: separator)...])) else { return nil }
        return (shortCode, kind)
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let (shortCode, kind) = Self.parse(taskDescription: downloadTask.taskDescription),
              kind == .video, totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        handlersLock.lock()
        let handler = progressHandlers[shortCode]
        handlersLock.unlock()
        handler?(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (shortCode, kind) = Self.parse(taskDescription: downloadTask.taskDescription) else { return }
        do {
            let destination = try kind == .video ? MediaStore.videoURL(shortCode: shortCode) : MediaStore.coverURL(shortCode: shortCode)
            // Must move synchronously here — the temp file at `location` is
            // deleted the instant this method returns.
            try MediaStore.moveDownloadedFile(from: location, to: destination)
        } catch {
            failed(shortCode: shortCode, error: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let (shortCode, _) = Self.parse(taskDescription: task.taskDescription) else { return }
        if let error {
            failed(shortCode: shortCode, error: error)
            return
        }
        // Fires (with error == nil) after a successful didFinishDownloadingTo
        // for either leg — this is where both assets are guaranteed to have
        // already been moved into place if they succeeded, so it's the right
        // point to check whether the pair is now complete.
        finalizeIfBothAssetsPresent(shortCode: shortCode)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        backgroundSessionCompletionHandler?()
        backgroundSessionCompletionHandler = nil
    }

    // MARK: - Completion bookkeeping

    private func finalizeIfBothAssetsPresent(shortCode: String) {
        guard MediaStore.hasVideo(shortCode: shortCode), MediaStore.hasCover(shortCode: shortCode) else { return }
        if let modelContainer {
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<Video>(predicate: #Predicate { $0.shortCode == shortCode })
            if let video = try? context.fetch(descriptor).first {
                video.fetched = true
                video.downloadedAt = .now
                try? context.save()
            }
        }
        complete(shortCode: shortCode, result: .success(()))
    }

    private func failed(shortCode: String, error: Error) {
        complete(shortCode: shortCode, result: .failure(error))
    }

    private func complete(shortCode: String, result: Result<Void, Error>) {
        handlersLock.lock()
        let handler = completionHandlers[shortCode]
        progressHandlers.removeValue(forKey: shortCode)
        completionHandlers.removeValue(forKey: shortCode)
        handlersLock.unlock()
        handler?(result)
    }
}
