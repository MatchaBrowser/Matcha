import Foundation

/// Blocklists shipped in a bundle's resources (task 6.2): the app, or the test bundle for its sample lists. Xcode
/// copies the resources of the synchronized folder flat (`Resources/Blocklists/x.json` ends up in
/// `Contents/Resources/x.json`); a `Blocklists` subfolder is also searched, in case it is kept.
nonisolated struct BlocklistBundle: Sendable {
    enum Error: Swift.Error, Equatable {
        /// The file of a list in the manifest is missing from the resources.
        case missingFile(String)
    }

    static let subdirectory = "Blocklists"

    let bundle: Bundle
    var manifestName = BlocklistManifest.resourceName

    /// Manifest of the lists; nil if there is none (no list shipped: the blocker stays inactive).
    func manifest() async throws -> BlocklistManifest? {
        guard let url = url(of: manifestName) else {
            return nil
        }
        return try await BlocklistManifest(data: Self.read(url))
    }

    /// Rules of `entry` (JSON in WebKit's format), read off the main thread.
    func rules(of entry: BlocklistEntry) async throws -> Data {
        guard let url = url(of: entry.file) else {
            throw Error.missingFile(entry.file)
        }
        return try await Self.read(url)
    }

    private func url(of name: String) -> URL? {
        bundle.url(forResource: name, withExtension: nil, subdirectory: Self.subdirectory)
            ?? bundle.url(forResource: name, withExtension: nil)
    }

    @concurrent
    private static func read(_ url: URL) async throws -> Data {
        try Data(contentsOf: url, options: .mappedIfSafe)
    }
}
