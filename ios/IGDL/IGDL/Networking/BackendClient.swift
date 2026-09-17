import Foundation

struct ResolvedPost: Decodable {
    let shortCode: String
    let videoURL: URL
    let coverURL: URL
    let caption: String
    let comments: [Comment]

    enum CodingKeys: String, CodingKey {
        case shortCode = "short_code"
        case videoURL = "video_url"
        case coverURL = "cover_url"
        case caption
        case comments
    }
}

enum BackendClientError: Error {
    case badStatusCode(Int, message: String?)
}

/// FastAPI's default HTTPException body shape (`{"detail": "..."}`) — used
/// to recover the actual reason (e.g. "post has no video") instead of just
/// the bare status code.
private struct BackendErrorBody: Decodable {
    let detail: String
}

/// Talks to the IGDL backend (see backend/app/main.py). One synchronous
/// call resolves a post to its CDN video/cover URLs, caption, and top
/// comments (via Instagram's own "top comments" GraphQL query — see
/// docs/plan.md) — the backend never downloads or stores the video itself,
/// it only needs an authenticated session to resolve URLs and comments.
/// The app downloads the actual video/cover directly from those CDN URLs
/// itself, via BackgroundDownloadCoordinator rather than this client.
final class BackendClient {
    // Backend is a personal single-user deployment (see docs/plan.md,
    // "Backend Deployment") — a static shared-secret header is enough auth
    // for that, no need for real user accounts/OAuth. The key is only ever
    // sent to our own backend host (resolve(shortCode:)), never to
    // Instagram's CDN, since it has no business being sent to a third
    // party. Lives in Secrets.swift, not here — this repo is public.
    private static let apiKey = Secrets.backendAPIKey

    static let shared = BackendClient(baseURL: URL(string: "https://igdl.jordys.site")!)

    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func resolve(shortCode: String) async throws -> ResolvedPost {
        var components = URLComponents(url: baseURL.appendingPathComponent("downloads/resolve"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "short_code", value: shortCode)]
        var request = URLRequest(url: components.url!)
        request.setValue(Self.apiKey, forHTTPHeaderField: "X-API-Key")
        // The backend serializes every resolve behind one global lock (only
        // one Instagram-facing call in flight at a time, deliberately — see
        // docs/plan.md) — DownloadManager sends up to 4 of these
        // concurrently, so a request can legitimately spend a while just
        // waiting its turn. The default 60s URLSession timeout was tight
        // enough to occasionally cancel a request still queued behind the
        // lock, which (since it never got a response) also never showed up
        // in the backend's own logs, making it look like the request never
        // arrived at all.
        request.timeoutInterval = 120
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, data: data)
        return try JSONDecoder().decode(ResolvedPost.self, from: data)
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = try? JSONDecoder().decode(BackendErrorBody.self, from: data).detail
            throw BackendClientError.badStatusCode(http.statusCode, message: message)
        }
    }
}
