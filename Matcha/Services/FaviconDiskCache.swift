import CoreGraphics
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Website icons kept on disk, one file per domain (`FaviconService`): a PNG of the decoded icon (128 pixels at most),
/// never the downloaded bytes (review SV3). Everything happens off the main thread. The cache holds `maximumFiles` at
/// most, the oldest erased first, and forgets the websites the history no longer has (review SV1).
nonisolated struct FaviconDiskCache: Sendable {
    /// Most files kept: beyond, the least recently written go.
    static let maximumFiles = 2000

    let directory: URL

    /// Name of the domain's file: letters, digits, dots and dashes; anything else becomes `_`.
    static func fileName(forHost host: String) -> String {
        String(host.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" })
    }

    func fileURL(forHost host: String) -> URL {
        directory.appendingPathComponent(Self.fileName(forHost: host), isDirectory: false)
    }

    /// The domain's file; nil if there is none, or beyond `maximumSize`.
    @concurrent
    func read(forHost host: String, maximumSize: Int) async -> Data? {
        let file = fileURL(forHost: host)
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maximumSize else {
            return nil
        }
        return try? Data(contentsOf: file)
    }

    /// Writes `image` as the domain's icon.
    @concurrent
    func write(_ image: CGImage, forHost host: String) async {
        guard let data = Self.png(of: image) else {
            Logger.favicons.error("Icon not encoded")
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(forHost: host), options: .atomic)
        } catch {
            Logger.favicons.error("Icon not saved to disk: \(error.logSummary, privacy: .public)")
        }
    }

    /// Erases the icons of `hosts`.
    @concurrent
    func remove(hosts: Set<String>) async {
        for host in hosts {
            try? FileManager.default.removeItem(at: fileURL(forHost: host))
        }
    }

    /// Erases every icon but those of `hosts`.
    @concurrent
    func removeAll(keeping hosts: Set<String>) async {
        let kept = Set(hosts.map(Self.fileName(forHost:)))
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles,
        )) ?? []
        var removed = 0
        for file in files where !kept.contains(file.lastPathComponent) {
            if (try? FileManager.default.removeItem(at: file)) != nil {
                removed += 1
            }
        }
        Logger.favicons.info("\(removed, privacy: .public) icons forgotten")
    }

    /// Keeps the `maximum` most recently written icons.
    @concurrent
    func trim(to maximum: Int = maximumFiles) async {
        let key = URLResourceKey.contentModificationDateKey
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [key],
            options: .skipsHiddenFiles,
        )) ?? []
        guard files.count > maximum else {
            return
        }
        let dated = files.map { (file: $0, date: (try? $0.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast) }
        for entry in dated.sorted(by: { $0.date > $1.date }).dropFirst(maximum) {
            try? FileManager.default.removeItem(at: entry.file)
        }
        Logger.favicons.info("Icon cache trimmed to \(maximum, privacy: .public) files")
    }

    private static func png(of image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
