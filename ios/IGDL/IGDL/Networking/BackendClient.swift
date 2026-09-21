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
struct BackendErrorBody: Decodable {
    let detail: String
}

/// Backend connection details (see backend/app/main.py). Just constants now
/// — the actual `/downloads/resolve` call used to live here as an async
/// method, but moved entirely into BackgroundDownloadCoordinator's
/// background URLSession (see docs/plan.md): a plain foreground request
/// only survives seconds of backgrounding, but the backend's own resolve
/// lock + breather can legitimately take much longer than that per call
/// (tens of seconds, deliberately, to avoid tripping Instagram's abuse
/// detection), and the whole point of an overnight batch is surviving the
/// phone actually sleeping for hours.
enum BackendClient {
    static let baseURL = URL(string: "https://igdl.jordys.site")!

    // Backend is a personal single-user deployment (see docs/plan.md,
    // "Backend Deployment") — a static shared-secret header is enough auth
    // for that, no need for real user accounts/OAuth. Sent only to this
    // backend host, never to Instagram's CDN. Lives in Secrets.swift, not
    // here — this repo is public.
    static let apiKey = Secrets.backendAPIKey
}
