import Foundation
import OSLog

/// Replaces a folder by another, with the old one kept aside (hidden, next to it) until the replacement is confirmed
/// (`finish`) or undone (`restore`, audit E6): an update that can't load gives back the previous version.
nonisolated struct FolderSwap {
    let destination: URL
    private let backup: URL?

    /// Moves `source` to `destination`; an existing `destination` goes aside first.
    init(placing source: URL, at destination: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.destination = destination
        if manager.fileExists(atPath: destination.path) {
            let aside = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).previous")
            try? manager.removeItem(at: aside)
            try manager.moveItem(at: destination, to: aside)
            backup = aside
        } else {
            backup = nil
        }
        do {
            try manager.moveItem(at: source, to: destination)
        } catch {
            if let backup {
                Self.moveBack(backup, to: destination)
            }
            throw error
        }
    }

    /// The new folder stays: the old one is deleted.
    func finish() {
        if let backup {
            try? FileManager.default.removeItem(at: backup)
        }
    }

    /// The old folder comes back (or nothing, if there was none).
    func restore() {
        try? FileManager.default.removeItem(at: destination)
        if let backup {
            Self.moveBack(backup, to: destination)
        }
    }

    /// Puts the previous version back; a failure is logged: the extension stays without its folder until reinstalled
    /// (review TR4).
    private static func moveBack(_ backup: URL, to destination: URL) {
        do {
            try FileManager.default.moveItem(at: backup, to: destination)
        } catch {
            Logger.extensions.error("Previous version not restored: \(error.logSummary, privacy: .public)")
        }
    }
}
