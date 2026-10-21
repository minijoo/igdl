import Foundation
import SwiftData

/// Runs a resolved post's entire pipeline — resolve, then video + cover —
/// through a single background URLSession, so a batch keeps going even
/// after the app is backgrounded, and even across the phone actually
/// sleeping for hours (an overnight batch).
///
/// This used to only cover the video/cover file transfers, with resolve
/// itself done as a plain foreground request driven by a live in-process
/// loop. That loop froze the instant iOS fully suspended the app — fine
/// when resolve was quick, but not once the backend started deliberately
/// pacing resolves tens of seconds apart (see docs/plan.md) to avoid
/// tripping Instagram's abuse detection: a real overnight run showed
/// downloads simply stopping (no errors, just frozen) the moment the phone
/// went to sleep. Routing resolve through the same background session as
/// the file transfers removes the live loop entirely — everything from
/// here on is delegate-driven, so nothing depends on this process staying
/// unsuspended.
///
/// A singleton, not per-screen state: the delegate has to exist and be
/// reachable the moment iOS relaunches the app in the background to deliver
/// a completed transfer, which can happen before any SwiftUI view (and
/// therefore before any DownloadManager) exists.
final class BackgroundDownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = BackgroundDownloadCoordinator()
    static let sessionIdentifier = "com.jordy.igdl.background-downloads"

    /// Read fresh per-task (see startResolve/start(url:...)) rather than
    /// baked into the session's own URLSessionConfiguration, specifically so
    /// toggling the setting takes effect immediately for the next thing
    /// enqueued — a session's own config is fixed for its lifetime, but
    /// URLRequest.allowsCellularAccess can be set per request. Defaults to
    /// false (Wi-Fi only) when unset, matching UserDefaults.bool(forKey:)'s
    /// own default — no separate "has the user chosen yet" bit needed.
    static let allowCellularDownloadsDefaultsKey = "allowCellularDownloads"

    private var allowsCellularAccess: Bool {
        UserDefaults.standard.bool(forKey: Self.allowCellularDownloadsDefaultsKey)
    }

    /// Set once from IGDLApp at launch. Needed here directly (not just handed
    /// down via SwiftUI's environment) because delegate callbacks can fire
    /// with no view hierarchy around to hand a ModelContext down from.
    var modelContainer: ModelContainer?

    /// Stashed by AppDelegate until this background session's queued
    /// delegate callbacks have all been delivered, per Apple's documented
    /// background-transfer completion handshake.
    var backgroundSessionCompletionHandler: (() -> Void)?

    private enum AssetKind: String { case resolve, video, cover }

    /// What a still-running task list means for the UI — recovered on
    /// (re)launch, see activeDownloads().
    enum RecoveredState {
        case resolving
        case downloading(progress: Double)
    }

    /// Per-shortCode callbacks, live only while a DownloadManager is around
    /// to receive them — safe to be missing (background relaunch with no UI
    /// up yet, or simply not re-registered after a fresh launch) since a
    /// finished transfer's actual result (the file on disk, the SwiftData
    /// writes) never depends on these being registered.
    private var progressHandlers: [String: (Double) -> Void] = [:]
    private var completionHandlers: [String: (Result<Void, Error>) -> Void] = [:]
    // Not cleared alongside progress/completion in complete(shortCode:) —
    // a task waiting for Wi-Fi hasn't completed, so there's nothing to
    // clear it for; it just stops firing once the task resumes and its
    // next progress/completion callback naturally overwrites the UI state.
    private var waitingForConnectivityHandlers: [String: () -> Void] = [:]
    private let handlersLock = NSLock()

    /// Resolves waiting for their turn, oldest first. The app only ever has
    /// `maxConcurrentResolves` resolve requests open at once (see
    /// pumpResolveQueue) instead of handing the whole batch to the OS up
    /// front: with N connections all held open with zero response bytes, one
    /// of them completing made nsurlsessiond drop and reissue *all* the
    /// others at once, a burst of N fresh requests every time — each of
    /// which the backend had to detect as disconnected/duplicated and re-queue.
    /// Persisted (not just in memory) so a batch survives the process being
    /// killed and relaunched in the background.
    private static let pendingResolvesDefaultsKey = "pendingResolveShortCodes"
    private static let maxConcurrentResolves = 1
    private var pumping = false
    private var pumpAgain = false

    private var pendingResolves: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.pendingResolvesDefaultsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.pendingResolvesDefaultsKey) }
    }

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

    /// Kicks off the whole pipeline for one video: resolve, then (once that
    /// comes back) video + cover — all as independent background tasks.
    /// Nothing here blocks waiting for a response; this returns immediately
    /// once the resolve task is registered with the session.
    func enqueueResolveAndDownload(
        shortCode: String,
        onProgress: @escaping (Double) -> Void,
        onWaitingForConnectivity: @escaping () -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        registerHandlers(shortCode: shortCode, onProgress: onProgress, onWaitingForConnectivity: onWaitingForConnectivity, onComplete: onComplete)
        handlersLock.lock()
        if !pendingResolves.contains(shortCode) { pendingResolves.append(shortCode) }
        handlersLock.unlock()
        pumpResolveQueue()
    }

    /// Starts queued resolves until `maxConcurrentResolves` are in flight.
    /// Called on enqueue and whenever a resolve task finishes; re-entrant
    /// calls just flag another pass, so two callers can never both see "0
    /// in flight" and each start one.
    private func pumpResolveQueue() {
        handlersLock.lock()
        if pumping {
            pumpAgain = true
            handlersLock.unlock()
            return
        }
        pumping = true
        handlersLock.unlock()

        Task {
            while true {
                handlersLock.withLock { pumpAgain = false }

                let inFlight = await session.allTasks.filter { task in
                    guard let (_, kind) = Self.parse(taskDescription: task.taskDescription) else { return false }
                    return kind == .resolve && (task.state == .running || task.state == .suspended)
                }.count

                let (next, again): (String?, Bool) = handlersLock.withLock {
                    var next: String?
                    if inFlight < Self.maxConcurrentResolves, !pendingResolves.isEmpty {
                        next = pendingResolves.removeFirst()
                        pumpAgain = true
                    }
                    if !pumpAgain { pumping = false }
                    return (next, pumpAgain)
                }

                if let next { startResolve(shortCode: next) }
                if !again { return }
            }
        }
    }

    func registerHandlers(
        shortCode: String,
        onProgress: @escaping (Double) -> Void,
        onWaitingForConnectivity: @escaping () -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        handlersLock.lock()
        progressHandlers[shortCode] = onProgress
        waitingForConnectivityHandlers[shortCode] = onWaitingForConnectivity
        completionHandlers[shortCode] = onComplete
        handlersLock.unlock()
    }

    /// Recovers shortCodes with a still-running task directly from the
    /// background session's own task list — used on (re)launch to repaint
    /// the "Downloading" section for a pipeline that outlived the previous
    /// process, instead of it looking empty until something finishes.
    func activeDownloads() async -> [String: RecoveredState] {
        var result: [String: RecoveredState] = [:]
        let pending = handlersLock.withLock { pendingResolves }
        for shortCode in pending { result[shortCode] = .resolving }
        for task in await session.allTasks {
            guard let (shortCode, kind) = Self.parse(taskDescription: task.taskDescription) else { continue }
            switch kind {
            case .resolve:
                if result[shortCode] == nil { result[shortCode] = .resolving }
            case .video:
                let expected = task.countOfBytesExpectedToReceive
                result[shortCode] = .downloading(progress: expected > 0 ? Double(task.countOfBytesReceived) / Double(expected) : 0)
            case .cover:
                // Only the video leg reports visible progress (matches prior
                // behavior); if only its cover task is left, the video side
                // is already done.
                if result[shortCode] == nil { result[shortCode] = .downloading(progress: 1) }
            }
        }
        return result
    }

    /// Cancels every in-flight resolve/video/cover task — a deliberate user
    /// action ("Cancel All Downloads"), not a failure, so this clears the
    /// handlers first rather than letting cancellation flow through the
    /// normal failed(...) path: nobody should see a "Cancelled" message on
    /// a batch they explicitly chose to stop, they should just see it gone.
    func cancelAllTasks() async {
        handlersLock.lock()
        progressHandlers.removeAll()
        waitingForConnectivityHandlers.removeAll()
        completionHandlers.removeAll()
        pendingResolves = []
        handlersLock.unlock()
        for task in await session.allTasks {
            task.cancel()
        }
    }

    private func startResolve(shortCode: String) {
        var components = URLComponents(url: BackendClient.baseURL.appendingPathComponent("downloads/resolve"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "short_code", value: shortCode)]
        var request = URLRequest(url: components.url!)
        request.setValue(BackendClient.apiKey, forHTTPHeaderField: "X-API-Key")
        request.allowsCellularAccess = allowsCellularAccess
        // The default 60s "no data received" timeout is far too short here:
        // the backend intentionally holds this connection open with zero
        // response bytes while the request queues behind a single global
        // lock plus a randomized breather (see docs/plan.md), which for a
        // multi-item batch can easily exceed 60s before this item's turn
        // comes up. Without a longer timeout, the OS kills and silently
        // retries the connection — the backend sees that as a brand-new
        // request for the same short_code, which re-enters the back of the
        // lock queue and can repeat indefinitely without ever completing.
        request.timeoutInterval = 1800
        let task = session.downloadTask(with: request)
        task.taskDescription = "\(shortCode)|\(AssetKind.resolve.rawValue)"
        task.resume()
    }

    private func start(url: URL, shortCode: String, kind: AssetKind) {
        var request = URLRequest(url: url)
        request.allowsCellularAccess = allowsCellularAccess
        let task = session.downloadTask(with: request)
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
        switch kind {
        case .resolve:
            handleResolveFinished(shortCode: shortCode, downloadTask: downloadTask, location: location)
        case .video, .cover:
            // A transfer "finishing" only means the response body was fully
            // received, not that it was actually the asset — an
            // expired/invalid CDN URL still "finishes downloading" a normal
            // error response body, which without this check would get
            // silently moved into MediaStore and marked fetched=true as if
            // it were a real video.
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                failed(shortCode: shortCode, error: BackendClientError.badStatusCode(http.statusCode, message: nil))
                return
            }
            do {
                let destination = try kind == .video ? MediaStore.videoURL(shortCode: shortCode) : MediaStore.coverURL(shortCode: shortCode)
                // Must move synchronously here — the temp file at `location`
                // is deleted the instant this method returns.
                try MediaStore.moveDownloadedFile(from: location, to: destination)
            } catch {
                failed(shortCode: shortCode, error: error)
            }
        }
    }

    /// Reads and fully handles a finished resolve task — decode, SwiftData
    /// writes, and (on success) kicking off the video/cover tasks — all
    /// synchronously here, since the temp file at `location` is gone the
    /// instant this returns and there's no other point this gets called
    /// back into.
    private func handleResolveFinished(shortCode: String, downloadTask: URLSessionDownloadTask, location: URL) {
        let data = (try? Data(contentsOf: location)) ?? Data()
        let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(statusCode) else {
            let message = try? JSONDecoder().decode(BackendErrorBody.self, from: data).detail
            if let modelContainer {
                ResolveHandling.markIncompatibleIfNeeded(shortCode: shortCode, message: message, context: ModelContext(modelContainer))
            }
            failed(shortCode: shortCode, error: BackendClientError.badStatusCode(statusCode, message: message))
            return
        }

        guard let resolved = try? JSONDecoder().decode(ResolvedPost.self, from: data) else {
            failed(shortCode: shortCode, error: BackendClientError.badStatusCode(statusCode, message: "invalid response"))
            return
        }

        if let modelContainer {
            try? ResolveHandling.saveMetadata(resolved: resolved, context: ModelContext(modelContainer))
        }

        start(url: resolved.videoURL, shortCode: shortCode, kind: .video)
        start(url: resolved.coverURL, shortCode: shortCode, kind: .cover)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let (shortCode, kind) = Self.parse(taskDescription: task.taskDescription) else { return }
        // Success or failure, this resolve's turn is over — start the next one.
        defer { if kind == .resolve { pumpResolveQueue() } }
        if let error {
            failed(shortCode: shortCode, error: error)
            return
        }
        switch kind {
        case .resolve:
            break // already fully handled in didFinishDownloadingTo
        case .video, .cover:
            // Fires (with error == nil) after a successful
            // didFinishDownloadingTo for either leg — this is where both
            // assets are guaranteed to have already been moved into place
            // if they succeeded, so it's the right point to check whether
            // the pair is now complete.
            finalizeIfBothAssetsPresent(shortCode: shortCode)
        }
    }

    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        // Fires when Wi-Fi-only is on (see allowsCellularAccess) and only
        // cellular is currently available — the task isn't failing, it's
        // just parked until a suitable network shows up, and will resume
        // (firing progress/completion normally) on its own once it does.
        guard let (shortCode, _) = Self.parse(taskDescription: task.taskDescription) else { return }
        handlersLock.lock()
        let handler = waitingForConnectivityHandlers[shortCode]
        handlersLock.unlock()
        handler?()
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
        // Logged here, not just by whatever's listening via onComplete —
        // this fires even when nothing is registered (e.g. the app was
        // relaunched purely to receive this callback, no DownloadManager
        // around), so this is the one place a failure is guaranteed to
        // leave a trace.
        NSLog("[IGDL] pipeline failed shortCode=%@ error=%@", shortCode, String(describing: error))
        complete(shortCode: shortCode, result: .failure(error))
    }

    private func complete(shortCode: String, result: Result<Void, Error>) {
        handlersLock.lock()
        let handler = completionHandlers[shortCode]
        progressHandlers.removeValue(forKey: shortCode)
        waitingForConnectivityHandlers.removeValue(forKey: shortCode)
        completionHandlers.removeValue(forKey: shortCode)
        handlersLock.unlock()
        handler?(result)
    }
}
