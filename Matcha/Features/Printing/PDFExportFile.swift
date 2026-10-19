import Foundation

/// File of “Export as PDF…” (task 5.4), with no dependency on the UI: proposed name and writing.
nonisolated enum PDFExportFile {
    /// Fallback name when the page has neither title nor host, never localized: it is a file name.
    static let fallbackName = "page"

    /// Proposed name: the page title made safe (“/” becomes “-”, like “:”), otherwise the host, otherwise the name of
    /// the local file, otherwise `fallbackName`; “.pdf” (or `fileExtension`) appended, 255 bytes at most.
    static func name(title: String?, url: URL?, fileExtension: String = "pdf") -> String {
        let candidates = [title, url?.host(percentEncoded: false), url.flatMap { $0.isFileURL ? $0.lastPathComponent : nil }]
        let base = candidates.lazy.compactMap { $0.map(baseName) }.first { !$0.isEmpty } ?? fallbackName
        return DownloadFileName.sanitized(base + "." + fileExtension)
    }

    /// Writes `data` in one go: into a temporary file on the same volume, which then takes the place of
    /// `destination` (a half-written file never replaces the old one). The temporary folder is the one the system
    /// provides for these replacements, allowed in the sandbox; failing that, the app's.
    static func write(_ data: Data, to destination: URL, fileManager: FileManager = .default) throws {
        let replacementDirectory = try? fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destination,
            create: true,
        )
        let temporary = (replacementDirectory ?? fileManager.temporaryDirectory)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        // The replacement folder is specific to this write: it goes away with the temporary file.
        defer {
            try? fileManager.removeItem(at: replacementDirectory ?? temporary)
        }
        try data.write(to: temporary)
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    /// Title without “/” or “\” (they would cut the name), without trailing “.pdf” or surrounding spaces and dots.
    private static func baseName(_ text: String) -> String {
        var name = DownloadFileName.sanitized(text.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-"))
        if name.lowercased().hasSuffix(".pdf") {
            name.removeLast(4)
        }
        return name.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
    }
}
