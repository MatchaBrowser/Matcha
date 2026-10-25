import CryptoKit
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

    /// True for an identifier of the form `random()` draws: the only one sync may propose (review EX10).
    static func isRandom(_ identifier: String) -> Bool {
        identifier.count == 32 && identifier.allSatisfy { ("0" ... "9").contains($0) || ("a" ... "f").contains($0) }
    }

    /// Safari extension of an app: prefix `safari-` and its bundle identifier; followed by a digest of the bundle
    /// identifier when another installed extension already has it (review EX4: “desktop-safari” and “desktop.safari”
    /// give the same text, never the same extension).
    static func forAppExtension(bundleIdentifier: String, avoiding taken: Set<String> = []) -> String? {
        guard let base = slug("safari-\(bundleIdentifier)") else {
            return nil
        }
        guard taken.contains(base) else {
            return base
        }
        let digest = SHA256.hash(data: Data(bundleIdentifier.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
        let prefix = base.prefix(ExtensionInstallDirectory.maximumIdentifierLength - digest.count - 1)
        return slug("\(prefix)-\(digest)")
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
