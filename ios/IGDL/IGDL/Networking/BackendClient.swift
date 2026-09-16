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
    case badStatusCode(Int)
}

/// Talks to the IGDL backend (see backend/app/main.py). One synchronous
/// call resolves a post to its CDN video/cover URLs, caption, and top
/// comments (via Instagram's own "top comments" GraphQL query — see
/// docs/plan.md) — the backend never downloads or stores the video itself,
/// it only needs an authenticated session to resolve URLs and comments.
/// The app downloads the actual video/cover directly from those CDN URLs.
final class BackendClient {
    // Backend is a personal single-user deployment (see docs/plan.md,
    // "Backend Deployment") — a static shared-secret header is enough auth
    // for that, no need for real user accounts/OAuth. The key is only ever
    // sent to our own backend host (resolve(shortCode:)), never to
    // Instagram's CDN (download(url:onProgress:) deliberately doesn't add
    // it), since it has no business being sent to a third party. Lives in
    // Secrets.swift, not here — this repo is public.
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
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response)
        return try JSONDecoder().decode(ResolvedPost.self, from: data)
    }

    /// Streams the response instead of downloading it in one shot, so
    /// `onProgress` can report real bytes-received-so-far for the video
    /// download. Fires at most once per 5% step, not per chunk, to avoid
    /// flooding observers with updates.
    func download(url: URL, onProgress: (Double) -> Void = { _ in }) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
        try Self.checkStatus(response)

        let expectedLength = response.expectedContentLength
        var data = Data()
        if expectedLength > 0 {
            data.reserveCapacity(Int(expectedLength))
        }

        var lastReportedStep = -1
        for try await byte in bytes {
            data.append(byte)
            if expectedLength > 0 {
                let step = Int((Double(data.count) / Double(expectedLength)) * 20)
                if step != lastReportedStep {
                    lastReportedStep = step
                    onProgress(Double(step) / 20)
                }
            }
        }
        return data
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendClientError.badStatusCode(http.statusCode)
        }
    }
}
