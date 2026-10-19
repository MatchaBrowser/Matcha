import Foundation
@testable import Matcha

/// Temporary folder specific to a test (in the app's container), deleted along with it.
@MainActor
final class TemporaryDownloadsFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("MatchaDownloads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Download manager that writes into this folder.
    func makeManager() -> DownloadManager {
        let url = url
        return DownloadManager(directory: { url })
    }

    /// Names of the folder's files, sorted.
    func contents() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
