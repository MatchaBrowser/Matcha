import Foundation

/// Reads the setup of a one-time code into a `totp` credential (`VAULT.md` § 9.2, § 9.7): an `otpauth://totp/…`
/// address (the Key Uri Format of Google Authenticator) or a bare base 32 secret. Only what Matcha computes is
/// accepted: SHA-1, SHA-256 or SHA-512, 6 to 8 digits, a period of 15 to 120 seconds. Pure type.
nonisolated enum VaultOTPAuth {
    static let algorithms: Set<String> = ["sha1", "sha256", "sha512"]
    static let digits = 6 ... 8
    static let periods = 15 ... 120

    /// The values of the setup.
    struct Setup: Equatable {
        var secret: String
        var algorithm = "sha1"
        var digits = 6
        var period = 30
        var issuer = ""

        /// The `totp` credential, without its `id`; nil outside what Matcha computes.
        var credential: VaultEntry? {
            let algorithm = algorithm.lowercased()
            guard let secret = VaultOTPAuth.normalizedSecret(secret), VaultOTPAuth.algorithms.contains(algorithm),
                  VaultOTPAuth.digits.contains(digits), VaultOTPAuth.periods.contains(period)
            else {
                return nil
            }
            var entry = VaultEntry(["type": .string(VaultCredentialType.totp)])
            entry.set("secret", secret)
            entry.set("algorithm", algorithm)
            entry.set("digits", integer: digits)
            entry.set("period", integer: period)
            entry.set("issuer", issuer)
            return entry
        }
    }

    /// The `totp` credential of `text`, an `otpauth://totp/` address or a base 32 secret; nil if it is neither, or
    /// outside what Matcha computes.
    static func credential(from text: String) -> VaultEntry? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("otpauth:") {
            return setup(fromURI: text)?.credential
        }
        return Setup(secret: text).credential
    }

    /// The setup of an `otpauth://totp/Issuer:account?secret=…&issuer=…&algorithm=…&digits=…&period=…` address; nil
    /// for another scheme or type (`hotp`), or without a secret.
    static func setup(fromURI text: String) -> Setup? {
        // Some exporters leave spaces in the label.
        guard let components = URLComponents(string: text) ?? URLComponents(string: text.replacingOccurrences(of: " ", with: "%20")),
              components.scheme?.lowercased() == "otpauth", components.host?.lowercased() == "totp"
        else {
            return nil
        }
        let items = components.queryItems ?? []
        let query = { (name: String) in items.first { $0.name.lowercased() == name }?.value ?? "" }
        guard !query("secret").isEmpty else {
            return nil
        }
        var setup = Setup(secret: query("secret"))
        setup.algorithm = query("algorithm").isEmpty ? "sha1" : query("algorithm")
        setup.digits = query("digits").isEmpty ? 6 : Int(query("digits")) ?? 0
        setup.period = query("period").isEmpty ? 30 : Int(query("period")) ?? 0
        // The issuer of the query, otherwise the label's prefix (“Issuer:account”).
        let label = String(components.path.drop { $0 == "/" })
        let prefix = label.contains(":") ? String(label.prefix { $0 != ":" }) : ""
        setup.issuer = query("issuer").isEmpty ? prefix.trimmingCharacters(in: .whitespaces) : query("issuer")
        return setup
    }

    /// The secret in uppercase, without spaces, hyphens or `=` padding (RFC 4648); nil if empty or not base 32.
    static func normalizedSecret(_ secret: String) -> String? {
        let cleaned = secret.uppercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "=" }
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        guard !cleaned.isEmpty, cleaned.allSatisfy(alphabet.contains) else {
            return nil
        }
        return cleaned
    }
}
