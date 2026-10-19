import Foundation

/// Stable identifier of an installed extension (task 6.4), valid for `ExtensionInstallDirectory`: it sets its address
/// (`webkit-extension://<identifier>/`) and its storage. Reinstalling the same extension (new version) gives the same
/// identifier: it replaces the old one and keeps its data. Pure type.
nonisolated enum ExtensionIdentifier {
    /// Extension from a file: its name in the manifest's default language (“Dark Reader” → `dark-reader`), otherwise
    /// its Firefox identifier; nil if neither gives an ASCII letter or digit.
    static func forPackage(_ file: ExtensionManifestFile) -> String? {
        file.name.flatMap(slug) ?? file.geckoIdentifier.flatMap(slug)
    }

    /// Safari extension of an app: prefix `safari-` and its bundle identifier.
    static func forAppExtension(bundleIdentifier: String) -> String? {
        slug("safari-\(bundleIdentifier)")
    }

    /// Name from the manifest, or its translated text (`__MSG_cle__`, key matched case-insensitively) taken from
    /// `messages` (`_locales/<default_locale>/messages.json`).
    static func name(in manifest: [String: Any], messages: [String: Any]?) -> String? {
        guard let raw = manifest["name"] as? String else {
            return nil
        }
        guard raw.hasPrefix("__MSG_"), raw.hasSuffix("__"), raw.count > 8 else {
            return raw
        }
        let key = raw.dropFirst(6).dropLast(2).lowercased()
        let entry = messages?.first { $0.key.lowercased() == key }?.value as? [String: Any]
        return entry?["message"] as? String
    }

    /// ASCII lowercase letters, digits and hyphens (accents removed, everything else becomes a hyphen), 63 characters
    /// at most; nil if nothing is left.
    static func slug(_ text: String) -> String? {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var result = ""
        for scalar in folded.lowercased().unicodeScalars {
            if ("a" ... "z").contains(scalar) || ("0" ... "9").contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else if !result.isEmpty, result.last != "-" {
                result.append("-")
            }
        }
        var trimmed = String(result.prefix(ExtensionInstallDirectory.maximumIdentifierLength))
        while trimmed.last == "-" {
            trimmed.removeLast()
        }
        return ExtensionInstallDirectory.isValidIdentifier(trimmed) ? trimmed : nil
    }
}
