import Foundation

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
