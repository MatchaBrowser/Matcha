import Foundation

/// Folder of the installed extensions (task 6.3): `Application Support/Extensions/<identifier>/`, one unpacked folder
/// per extension, with its `manifest.json`. The folder name is the extension's identifier: it gives its address
/// (`webkit-extension://<identifier>/`) and its storage, which must stay the same from one launch to the next. The
/// installer puts the extensions installed from a file there (`ExtensionInstaller`). Pure type.
nonisolated enum ExtensionInstallDirectory {
    static let folderName = "Extensions"
    static let manifestName = "manifest.json"
    /// Maximum length of an identifier (a host label).
    static let maximumIdentifierLength = 63

    /// True if `identifier` can be used as an identifier: ASCII lowercase letters, digits and hyphens, no hyphen at the
    /// start or the end, 63 characters at most (it becomes the host of the address of the extension's pages).
    static func isValidIdentifier(_ identifier: String) -> Bool {
        guard !identifier.isEmpty, identifier.count <= maximumIdentifierLength,
              identifier.first != "-", identifier.last != "-"
        else {
            return false
        }
        return identifier.unicodeScalars.allSatisfy { ("a" ... "z").contains($0) || ("0" ... "9").contains($0) || $0 == "-" }
    }

    /// Extensions folder in `applicationSupport`.
    static func directory(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Extensions present in `directory`: (identifier, folder), sorted by identifier. A folder with an invalid name or
    /// without `manifest.json`, a file or a hidden folder is ignored. Missing folder: none.
    static func installedExtensions(in directory: URL, fileManager: FileManager = .default) -> [(identifier: String, url: URL)] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        )) ?? []
        return contents
            .filter { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return isDirectory && isValidIdentifier(url.lastPathComponent)
                    && fileManager.fileExists(atPath: url.appendingPathComponent(manifestName).path)
            }
            .map { (identifier: $0.lastPathComponent, url: $0) }
            .sorted { $0.identifier < $1.identifier }
    }
}
