import Foundation

/// Download progress, without UI dependency: received fraction of one download, and of all those in progress for
/// the ring of the sidebar button.
nonisolated enum DownloadProgressSummary {
    /// Received fraction, from 0 to 1; nil if the size is unknown.
    static func fraction(completed: Int64, total: Int64?) -> Double? {
        guard let total, total > 0 else {
            return nil
        }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    /// Received fraction of all downloads in progress, weighted by their size; nil if one of them has an unknown
    /// size (the ring cannot promise anything then) or if there are none.
    static func overallFraction(of downloads: [(completed: Int64, total: Int64?)]) -> Double? {
        guard !downloads.isEmpty else {
            return nil
        }
        var completed: Int64 = 0
        var total: Int64 = 0
        for download in downloads {
            guard let size = download.total, size > 0 else {
                return nil
            }
            completed += min(max(0, download.completed), size)
            total += size
        }
        return fraction(completed: completed, total: total)
    }

    /// Readable size (“12 MB”), in the user's language, like the Finder.
    static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
