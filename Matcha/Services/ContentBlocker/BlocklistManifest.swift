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

/// A list in the manifest (`BlocklistManifest`).
nonisolated struct BlocklistEntry: Codable, Hashable, Sendable {
    /// Stable identifier: lowercase letters, digits and hyphens (“easylist”).
    let identifier: String
    /// Name shown in the settings (“EasyList”).
    let name: String
    /// Version of the list (“2026.10.18”): letters, digits, dots, hyphens and underscores.
    let version: String
    /// Name of the JSON file among the resources, without a folder.
    let file: String
    /// License shown in the settings (“CC BY-SA 3.0”).
    var license: String?
    /// Website of the list, shown in the settings (https only).
    var homepage: String?

    init(identifier: String, name: String, version: String, file: String, license: String? = nil, homepage: String? = nil) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.file = file
        self.license = license
        self.homepage = homepage
    }

    /// Address of the list's website, if it uses https.
    var homepageURL: URL? {
        guard let homepage, let url = URL(string: homepage), url.scheme?.lowercased() == "https", url.host() != nil else {
            return nil
        }
        return url
    }

    var isValid: Bool {
        Self.isToken(identifier, extra: "-", maximumLength: 64)
            && identifier.allSatisfy { !$0.isUppercase }
            && Self.isToken(version, extra: ".-_", maximumLength: 64)
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && file.hasSuffix(".json") && file.count > 5 && !file.contains("/") && !file.hasPrefix(".")
    }

    /// True if `text` is made only of ASCII letters and digits and of `extra`, starts with a letter or a digit, and is
    /// no longer than `maximumLength` characters.
    private static func isToken(_ text: String, extra: String, maximumLength: Int) -> Bool {
        guard let first = text.first, first.isASCII, first.isLetter || first.isNumber, text.count <= maximumLength else {
            return false
        }
        return text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || extra.contains($0)) }
    }
}
