import Foundation

/// Stable identifier of an installed extension (task 6.4), valid for `ExtensionInstallDirectory`: it sets its address
/// (`webkit-extension://<identifier>/`) and its storage. Pure type.
nonisolated enum ExtensionIdentifier {
    /// Extension from a file (audit E1): random, kept for its whole life (updates from the same publisher keep it).
    /// Never derived from its name: another file with the same name would inherit its data, and websites could guess
    /// its address. 32 hexadecimal characters, which a Safari extension's (`safari-…`) can't be.
    static func random() -> String {
        UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
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
