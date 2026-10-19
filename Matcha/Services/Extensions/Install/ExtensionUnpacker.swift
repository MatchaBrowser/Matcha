import Foundation

/// Unpacks a chosen extension file or folder into a temporary folder, off the main thread (audit E6): a `.crx`,
/// `.xpi` or `.zip` file (its publisher read from a CRX3 signature), or a folder copied file by file without its
/// symbolic links (audit E3: a link could make the extension read the app's own data). Never more than
/// `maximumSize` bytes or `maximumEntries` files.
nonisolated enum ExtensionUnpacker {
    enum Failure: Error, Equatable {
        case tooLarge
        /// The folder holds a symbolic link or an alias: refused rather than followed.
        case link
    }

    static let maximumSize = 256 * 1024 * 1024
    static let maximumEntries = 20000

    /// Unpacks `url` into `staging` (created) and returns the publisher proven by a CRX3 signature, if any.
    @concurrent
    static func unpack(_ url: URL, into staging: URL) async throws -> String? {
        let manager = FileManager.default
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            try copyFolder(url, to: staging)
            return nil
        }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumSize else {
            throw Failure.tooLarge
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let publisher = CRXSignature.verifiedPublisher(of: data)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        try ZipArchive(data: ExtensionPackage.zipData(from: data)).extract(to: staging)
        return publisher
    }

    /// Copies the regular files and folders of `source` to `destination`; refuses a symbolic link or an alias.
    static func copyFolder(_ source: URL, to destination: URL) throws {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey, .fileSizeKey]
        guard let enumerator = manager.enumerator(at: source, includingPropertiesForKeys: keys) else {
            throw CocoaError(.fileReadUnknown)
        }
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let base = source.standardizedFileURL.path
        var total = 0
        var count = 0
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true, values.isAliasFile != true else {
                throw Failure.link
            }
            count += 1
            total += values.fileSize ?? 0
            guard count <= maximumEntries, total <= maximumSize else {
                throw Failure.tooLarge
            }
            let relative = String(item.standardizedFileURL.path.dropFirst(base.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let target = destination.appendingPathComponent(relative)
            if values.isDirectory == true {
                try manager.createDirectory(at: target, withIntermediateDirectories: true)
            } else if values.isRegularFile == true {
                try manager.copyItem(at: item, to: target)
            }
        }
    }
}
