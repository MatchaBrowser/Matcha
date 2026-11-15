import CryptoKit
import Foundation

/// A time-based one-time code (TOTP, RFC 6238 over HOTP, RFC 4226), as a vault credential holds it (`VAULT.md`
/// § 9.7): the shared secret, the HMAC algorithm, 6 to 8 digits and a period of 15 to 120 seconds (30 by default),
/// with the issuer and the account it was given for. The code is computed from the date it is given, this Mac's
/// clock in the app. Read from and written to an `otpauth://totp/…` address (`OneTimeCode+URI.swift`). Pure type.
nonisolated struct OneTimeCode: Equatable, Sendable {
    /// The HMAC hash function; the raw value is the one stored in a vault item.
    enum Algorithm: String, CaseIterable, Sendable {
        case sha1
        case sha256
        case sha512
    }

    enum Error: Swift.Error, Equatable {
        /// The secret is empty, longer than `maximumSecretLength`, or not valid base 32 in an address.
        case invalidSecret
        /// The number of digits is outside `digitsRange`, or not a number in an address.
        case digitsOutOfRange
        /// The period is outside `periodRange`, or not a number in an address.
        case periodOutOfRange
        /// The address isn't `otpauth://totp/…`.
        case unsupportedAddress
        /// An `otpauth://hotp/…` address: codes driven by a counter are not supported.
        case counterBased
        /// The address has no `secret`.
        case missingSecret
        /// The address's `algorithm` is not SHA1, SHA256 or SHA512.
        case unsupportedAlgorithm
    }

    static let digitsRange = 6 ... 8
    static let periodRange = 15 ... 120
    static let defaultDigits = 6
    static let defaultPeriod = 30
    /// Ceiling of the secret, in bytes: services give 10 to 64.
    static let maximumSecretLength = 1024

    let secret: Data
    let algorithm: Algorithm
    let digits: Int
    /// In seconds.
    let period: Int
    /// The service the code is for (“GitHub”); nil if unknown. Not part of the code.
    var issuer: String?
    /// The account on that service, usually its user name; nil if unknown. Not part of the code.
    var account: String?

    /// Parameters checked: a secret of 1 to `maximumSecretLength` bytes, `digits` within `digitsRange`, `period` within
    /// `periodRange`.
    init(secret: Data, algorithm: Algorithm = .sha1, digits: Int = defaultDigits, period: Int = defaultPeriod) throws {
        guard !secret.isEmpty, secret.count <= Self.maximumSecretLength else {
            throw Error.invalidSecret
        }
        guard Self.digitsRange.contains(digits) else {
            throw Error.digitsOutOfRange
        }
        guard Self.periodRange.contains(period) else {
            throw Error.periodOutOfRange
        }
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }

    /// The code at `date`, padded with zeros to `digits` (RFC 6238 § 4).
    func code(at date: Date) -> String {
        code(counter: counter(at: date))
    }

    /// Seconds before the code at `date` changes, from `period` down to 1.
    func secondsRemaining(at date: Date) -> Int {
        period - Int(Self.seconds(at: date) % Int64(period))
    }

    /// The number of periods elapsed since 1970 at `date` (RFC 6238's `T`); 0 before 1970.
    func counter(at date: Date) -> UInt64 {
        UInt64(Self.seconds(at: date) / Int64(period))
    }

    /// The HOTP value for `counter` (RFC 4226 § 5.3): HMAC of the counter in big-endian, dynamic truncation to 31 bits,
    /// then its last `digits` decimal digits.
    func code(counter: UInt64) -> String {
        let mac = Array(authenticationCode(for: withUnsafeBytes(of: counter.bigEndian) { Data($0) }))
        let offset = Int(mac[mac.count - 1] & 0x0F)
        let truncated = UInt32(mac[offset] & 0x7F) << 24
            | UInt32(mac[offset + 1]) << 16
            | UInt32(mac[offset + 2]) << 8
            | UInt32(mac[offset + 3])
        let modulus = (0 ..< digits).reduce(UInt32(1)) { value, _ in value * 10 }
        let value = String(truncated % modulus)
        return String(repeating: "0", count: digits - value.count) + value
    }

    private func authenticationCode(for message: Data) -> Data {
        let key = SymmetricKey(data: secret)
        return switch algorithm {
        case .sha1: Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
    }

    /// Whole seconds since 1970 at `date`: 0 before (or for a date that isn't a number), `Int64.max` for one too far.
    private static func seconds(at date: Date) -> Int64 {
        let seconds = date.timeIntervalSince1970.rounded(.down)
        guard seconds > 0 else {
            return 0
        }
        return seconds < 9e18 ? Int64(seconds) : Int64.max
    }
}
