import Foundation

/// Persists downloaded media in the app's sandbox, keyed by short_code —
/// not in the Photos app. Uses Application Support rather than Documents so
/// it isn't exposed to the user via the Files app.
enum MediaStore {
    private static func directory(for shortCode: String) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("media", isDirectory: true)
            .appendingPathComponent(shortCode, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func videoURL(shortCode: String) throws -> URL {
        try directory(for: shortCode).appendingPathComponent("video.mp4")
    }

    static func coverURL(shortCode: String) throws -> URL {
        try directory(for: shortCode).appendingPathComponent("cover.jpg")
    }

    static func commentsURL(shortCode: String) throws -> URL {
        try directory(for: shortCode).appendingPathComponent("comments.json")
    }

    static func save(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    static func hasVideo(shortCode: String) -> Bool {
        (try? videoURL(shortCode: shortCode)).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    static func hasCover(shortCode: String) -> Bool {
        (try? coverURL(shortCode: shortCode)).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// Moves a background URLSessionDownloadTask's temp file into permanent
    /// storage — that temp file is deleted the instant the delegate callback
    /// handing it to us returns, so this has to happen synchronously there,
    /// not via a Data round-trip.
    static func moveDownloadedFile(from tempURL: URL, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
    }
}
