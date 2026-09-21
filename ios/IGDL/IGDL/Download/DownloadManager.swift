import Foundation
import SwiftData
import Observation

enum DownloadItemState: Equatable {
    case notStarted
    case resolving // asking the backend for CDN URLs + comments
    // Wi-Fi-only is on (see Settings) and only cellular is currently
    // available — not a failure, the task is just parked until a suitable
    // network shows up, and resumes on its own (moving back to .resolving
    // or .downloadingVideo) once it does.
    case waitingForWiFi
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

/// Mirrors BackgroundDownloadCoordinator's progress/completion callbacks
/// into UI state. That's *all* this does now — every part of actually
/// resolving and downloading a video runs through the coordinator's
/// background URLSession (see docs/plan.md), not any live loop here. That's
/// deliberate: a loop driven by this (regular, suspendable) process would
/// freeze the moment iOS suspends the app — which is exactly what used to
/// stall an overnight batch the instant the phone went to sleep, even
/// though the file transfers themselves kept going. There's nothing left
/// for this class to throttle or sequence either — the backend fully
/// serializes and paces every resolve itself, and the background session
/// tolerates a task sitting queued for however long that takes.
@Observable
@MainActor
final class DownloadManager {
    private(set) var states: [String: DownloadItemState] = [:]

    private let coordinator: BackgroundDownloadCoordinator

    init(coordinator: BackgroundDownloadCoordinator = .shared) {
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
        for (shortCode, state) in await coordinator.activeDownloads() {
            switch state {
            case .resolving:
                states[shortCode] = .resolving
            case .downloading(let progress):
                states[shortCode] = .downloadingVideo(progress: progress)
            }
            coordinator.registerHandlers(
                shortCode: shortCode,
                onProgress: { [weak self] progress in
                    Task { @MainActor in self?.states[shortCode] = .downloadingVideo(progress: progress) }
                },
                onWaitingForConnectivity: { [weak self] in
                    Task { @MainActor in self?.states[shortCode] = .waitingForWiFi }
                },
                onComplete: { [weak self] result in
                    Task { @MainActor in self?.apply(result, to: shortCode) }
                }
            )
        }
    }

    /// Enqueues every selected video's whole pipeline immediately — no
    /// client-side batching or throttling. Returns as soon as each one is
    /// registered with the background session, not when any of them finish.
    func downloadSelected(shortCodes: [String]) {
        for shortCode in shortCodes {
            states[shortCode] = .resolving
            coordinator.enqueueResolveAndDownload(
                shortCode: shortCode,
                onProgress: { [weak self] progress in
                    Task { @MainActor in self?.states[shortCode] = .downloadingVideo(progress: progress) }
                },
                onWaitingForConnectivity: { [weak self] in
                    Task { @MainActor in self?.states[shortCode] = .waitingForWiFi }
                },
                onComplete: { [weak self] result in
                    Task { @MainActor in self?.apply(result, to: shortCode) }
                }
            )
        }
    }

    /// Stops every in-flight resolve/video/cover task and clears them back
    /// to the plain selectable list — an explicit user action, not a
    /// failure, so states are wiped directly rather than routed through
    /// apply(_:to:) (which would otherwise show them as "Failed —
    /// Cancelled" and need an individual tap-to-retry each).
    func cancelAll() async {
        await coordinator.cancelAllTasks()
        states.removeAll()
    }

    private func apply(_ result: Result<Void, Error>, to shortCode: String) {
        switch result {
        case .success:
            states[shortCode] = .done
        case .failure(let error):
            states[shortCode] = .failed(Self.describe(error))
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
}
