import Foundation
import OSLog

/// A download as the list keeps it from one launch to the next: only those of regular windows, never those of
/// private windows. Neither the requested address nor the originating page. Pure type.
nonisolated struct SavedDownload: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case finished
        case failed
        case cancelled
        /// In progress when the app was quit (its partial file is deleted).
        case interrupted
    }

    var id: UUID
    var fileName: String
    var fileURL: URL?
    var outcome: Outcome
    /// Size of the written file, or received part.
    var byteCount: Int64
    /// Reason for a failure, in the user's language at the time of the failure.
    var failureReason: String?
}

/// Downloads list kept in the app's settings (`downloadsList`, JSON), from newest to oldest, until the user clears
/// it (“Clear”).
nonisolated enum SavedDownloadList {
    static let defaultsKey = "downloadsList"
    /// The oldest ones beyond this are no longer kept.
    static let limit = 100

    /// Saved list; empty if nothing is saved or if the value is unreadable.
    static func load(from defaults: UserDefaults) -> [SavedDownload] {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([SavedDownload].self, from: data)
        } catch {
            Logger.downloads.error("Liste des téléchargements illisible : \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Saves `downloads` (the first `limit`); an empty list removes the value.
    static func save(_ downloads: [SavedDownload], to defaults: UserDefaults) {
        guard !downloads.isEmpty else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        do {
            try defaults.set(JSONEncoder().encode(Array(downloads.prefix(limit))), forKey: defaultsKey)
        } catch {
            Logger.downloads.error("Liste des téléchargements non enregistrée : \(error.localizedDescription, privacy: .public)")
        }
    }
}
