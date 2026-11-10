import Foundation

/// The `otpauth://` address of a code (Google Authenticator's “Key Uri Format”), read when the user pastes it or scans
/// its QR code, written back for an export:
/// `otpauth://totp/Issuer:account?secret=…&issuer=Issuer&algorithm=SHA1&digits=6&period=30`.
nonisolated extension OneTimeCode {
    private static let scheme = "otpauth"
    /// Characters written as they are in the label and the parameters: RFC 3986's unreserved ones, plus `@` (an
    /// account is often an email address). Everything else is percent-encoded, the colon included.
    private static let unencoded = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~@")

    /// Code read from an `otpauth://totp/…` address. The label (`Issuer:account`, percent-decoded, its colon literal
    /// or encoded) gives the account and, unless an `issuer` parameter is given, the issuer. `secret` is required;
    /// `algorithm`, `digits` and `period` default to SHA1, 6 and 30; unknown parameters are ignored. A `hotp` address
    /// is refused (`Error.counterBased`).
    init(otpauth url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme
        else {
            throw Error.unsupportedAddress
        }
        switch components.host?.lowercased() {
        case "totp": break
        case "hotp": throw Error.counterBased
        default: throw Error.unsupportedAddress
        }
        let parameters = Self.parameters(of: components)
        guard let encodedSecret = parameters["secret"] else {
            throw Error.missingSecret
        }
        guard let secret = try? Base32.decode(encodedSecret) else {
            throw Error.invalidSecret
        }
        try self.init(
            secret: secret,
            algorithm: Self.algorithm(named: parameters["algorithm"]),
            digits: Self.number(parameters["digits"], absent: Self.defaultDigits, invalid: .digitsOutOfRange),
            period: Self.number(parameters["period"], absent: Self.defaultPeriod, invalid: .periodOutOfRange),
        )
        let label = Self.label(ofEncodedPath: components.percentEncodedPath)
        issuer = Self.nonEmpty(parameters["issuer"]) ?? label.issuer
        account = label.account
    }

    /// Code read from the text of an `otpauth://totp/…` address, white space around it ignored; nil if it isn't one
    /// or its parameters are invalid.
    init?(uri: String) {
        guard let url = URL(string: uri.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        do {
            try self.init(otpauth: url)
        } catch {
            return nil
        }
    }

    /// The address of the code, every parameter written (`secret` in base 32 without padding, `issuer` if known), which
    /// `init(uri:)` reads back to the same code.
    var uri: String {
        let knownIssuer = Self.nonEmpty(issuer)
        let encodedAccount = Self.encoded(Self.nonEmpty(account) ?? "")
        // A colon in an account without issuer is encoded, but an encoded colon also separates issuer and account:
        // a leading empty issuer keeps the account whole.
        let label = if let knownIssuer {
            Self.encoded(knownIssuer) + ":" + encodedAccount
        } else if encodedAccount.contains("%3A") {
            ":" + encodedAccount
        } else {
            encodedAccount
        }
        var parameters = ["secret=" + Base32.encode(secret)]
        if let knownIssuer {
            parameters.append("issuer=" + Self.encoded(knownIssuer))
        }
        parameters += ["algorithm=" + algorithm.rawValue.uppercased(), "digits=\(digits)", "period=\(period)"]
        return "\(Self.scheme)://totp/\(label)?" + parameters.joined(separator: "&")
    }

    /// The parameters by lowercase name, decoded; the first one wins when a name is repeated.
    private static func parameters(of components: URLComponents) -> [String: String] {
        var parameters: [String: String] = [:]
        for item in components.queryItems ?? [] where parameters[item.name.lowercased()] == nil {
            parameters[item.name.lowercased()] = item.value ?? ""
        }
        return parameters
    }

    /// SHA1 when absent; `SHA1`, `SHA256` or `SHA512` in any case, with or without a hyphen.
    private static func algorithm(named name: String?) throws -> Algorithm {
        guard let name else {
            return .sha1
        }
        guard let algorithm = Algorithm(rawValue: name.lowercased().replacingOccurrences(of: "-", with: "")) else {
            throw Error.unsupportedAlgorithm
        }
        return algorithm
    }

    /// `absent` when there is no value, `invalid` thrown when it isn't a whole number; the range is the initializer's
    /// to check.
    private static func number(_ text: String?, absent: Int, invalid: Error) throws -> Int {
        guard let text else {
            return absent
        }
        guard let number = Int(text) else {
            throw invalid
        }
        return number
    }

    /// Issuer and account of the label: split at the first literal colon, or else at the first encoded one, before
    /// decoding, so that a colon encoded inside a name stays in it; white space around each part is dropped.
    private static func label(ofEncodedPath path: String) -> (issuer: String?, account: String?) {
        let label = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let separator = label.range(of: ":") ?? label.range(of: "%3A", options: .caseInsensitive) else {
            return (nil, decoded(label))
        }
        return (decoded(label[..<separator.lowerBound]), decoded(label[separator.upperBound...]))
    }

    /// Percent-decoded and trimmed; the text as it is if its encoding is invalid, nil if empty.
    private static func decoded(_ text: some StringProtocol) -> String? {
        nonEmpty(text.removingPercentEncoding ?? String(text))
    }

    private static func encoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unencoded) ?? ""
    }

    /// `text` trimmed of white space; nil if nothing is left.
    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
