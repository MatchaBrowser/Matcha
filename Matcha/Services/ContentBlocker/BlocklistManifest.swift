import Foundation

/// Manifest of the blocklists shipped in the app (task 6.2): `Resources/Blocklists/blocklists.json`, filled by task
/// 6.1. For each list in WebKit's content blocking format: its identifier (stable from one version to the next), its
/// display name, its version (a new version makes it recompile at the next launch), its file, and for the settings its
/// license and its website. The app's resources are copied flat: each file must have a unique name among them
/// (`blocklist-<identifier>.json`). An invalid entry, or one whose identifier is already taken, is skipped.
///
/// ```json
/// { "format" : 1,
///   "lists" : [ { "identifier" : "easylist", "name" : "EasyList", "version" : "2026.10.18",
///                 "file" : "blocklist-easylist.json", "license" : "CC BY-SA 3.0", "homepage" : "https://easylist.to" } ] }
/// ```
nonisolated struct BlocklistManifest: Equatable, Sendable {
    /// Version of the manifest format understood by this version of Matcha.
    static let supportedFormat = 1
    /// Name of the manifest among the app's resources.
    static let resourceName = "blocklists.json"

    enum Error: Swift.Error, Equatable {
        /// Manifest in a newer format than the one this version understands.
        case unsupportedFormat(Int)
    }

    /// Valid lists, in manifest order.
    let lists: [BlocklistEntry]

    init(lists: [BlocklistEntry]) {
        var seen: Set<String> = []
        self.lists = lists.filter { $0.isValid && seen.insert($0.identifier).inserted }
    }

    /// Reads a manifest; throws if the JSON is unreadable or in an unknown format.
    init(data: Data) throws {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        guard raw.format == Self.supportedFormat else {
            throw Error.unsupportedFormat(raw.format)
        }
        self.init(lists: raw.lists.compactMap(\.entry))
    }

    private struct Raw: Decodable {
        let format: Int
        let lists: [LenientEntry]
    }

    /// An unreadable entry (missing field, wrong type) is skipped without rejecting the whole manifest.
    private struct LenientEntry: Decodable {
        let entry: BlocklistEntry?

        init(from decoder: any Decoder) throws {
            entry = try? BlocklistEntry(from: decoder)
        }
    }
}
