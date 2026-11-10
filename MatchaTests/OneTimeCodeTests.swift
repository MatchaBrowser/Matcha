import Foundation
@testable import Matcha
import Testing

/// One-time codes (`VAULT.md` § 9.7 and § 12): the RFC 6238 and RFC 4226 vectors, the bounds of the parameters, and
/// the `otpauth://` addresses of Google Authenticator's “Key Uri Format”.
struct OneTimeCodeTests {
    /// RFC 6238, appendix B: the ASCII secrets of each algorithm.
    private static let rfcSecrets: [OneTimeCode.Algorithm: String] = [
        .sha1: "12345678901234567890",
        .sha256: "12345678901234567890123456789012",
        .sha512: "1234567890123456789012345678901234567890123456789012345678901234",
    ]
    /// `JBSWY3DPEHPK3PXP`, the secret of Google's example.
    private static let helloSecret = Data("Hello!".utf8) + Data([0xDE, 0xAD, 0xBE, 0xEF])

    private func rfcCode(_ algorithm: OneTimeCode.Algorithm, digits: Int = 8) throws -> OneTimeCode {
        let secret = try #require(Self.rfcSecrets[algorithm])
        return try OneTimeCode(secret: Data(secret.utf8), algorithm: algorithm, digits: digits)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    // MARK: Vectors

    /// RFC 6238, appendix B: the time, then the 8-digit codes for SHA-1, SHA-256 and SHA-512.
    private static let rfcVectors: [(TimeInterval, [String])] = [
        (59, ["94287082", "46119246", "90693936"]),
        (1_111_111_109, ["07081804", "68084774", "25091201"]),
        (1_111_111_111, ["14050471", "67062674", "99943326"]),
        (1_234_567_890, ["89005924", "91819424", "93441116"]),
        (2_000_000_000, ["69279037", "90698825", "38618901"]),
        (20_000_000_000, ["65353130", "77737706", "47863826"]),
    ]

    @Test(arguments: rfcVectors)
    func `codes match the RFC 6238 vectors`(seconds: TimeInterval, expected: [String]) throws {
        for (algorithm, code) in zip([OneTimeCode.Algorithm.sha1, .sha256, .sha512], expected) {
            #expect(try rfcCode(algorithm).code(at: date(seconds)) == code, "\(algorithm) at \(seconds)")
        }
    }

    @Test func `the truncation matches the RFC 4226 HOTP values`() throws {
        let code = try rfcCode(.sha1, digits: 6)
        let expected = ["755224", "287082", "359152", "969429", "338314", "254676", "287922", "162583", "399871", "520489"]
        #expect((0 ..< 10).map { code.code(counter: UInt64($0)) } == expected)
    }

    @Test func `the counter and the remaining seconds follow the period`() throws {
        let code = try rfcCode(.sha1)
        #expect(code.counter(at: date(59)) == 1)
        #expect(code.counter(at: date(1_111_111_109)) == 0x0235_23EC)
        #expect(code.counter(at: date(20_000_000_000)) == 0x27BC_86AA)
        #expect(code.secondsRemaining(at: date(0)) == 30)
        #expect(code.secondsRemaining(at: date(59)) == 1)
        #expect(code.secondsRemaining(at: date(59.9)) == 1)
        #expect(code.secondsRemaining(at: date(60)) == 30)
        #expect(code.secondsRemaining(at: date(-100)) == 30)
        let minute = try OneTimeCode(secret: Data("12345678901234567890".utf8), period: 60)
        #expect(minute.secondsRemaining(at: date(61)) == 59)
        #expect(minute.code(at: date(119)) == String(code.code(counter: 1).suffix(6)))
    }

    @Test func `codes of 6 and 7 digits are the last digits of the 8-digit one`() throws {
        let eight = try rfcCode(.sha256).code(at: date(1_111_111_109))
        #expect(try rfcCode(.sha256, digits: 6).code(at: date(1_111_111_109)) == String(eight.suffix(6)))
        #expect(try rfcCode(.sha256, digits: 7).code(at: date(1_111_111_109)) == String(eight.suffix(7)))
    }

    // MARK: Bounds

    @Test func `parameters out of bounds are refused`() throws {
        let secret = Data("12345678901234567890".utf8)
        #expect(throws: OneTimeCode.Error.invalidSecret) { try OneTimeCode(secret: Data()) }
        #expect(throws: OneTimeCode.Error.invalidSecret) { try OneTimeCode(secret: Data(count: 1025)) }
        #expect(throws: OneTimeCode.Error.digitsOutOfRange) { try OneTimeCode(secret: secret, digits: 5) }
        #expect(throws: OneTimeCode.Error.digitsOutOfRange) { try OneTimeCode(secret: secret, digits: 9) }
        #expect(throws: OneTimeCode.Error.periodOutOfRange) { try OneTimeCode(secret: secret, period: 14) }
        #expect(throws: OneTimeCode.Error.periodOutOfRange) { try OneTimeCode(secret: secret, period: 121) }
        for (digits, period) in [(6, 15), (8, 120)] {
            let code = try OneTimeCode(secret: secret, digits: digits, period: period)
            #expect(code.code(at: date(1_234_567_890)).count == digits)
        }
        let defaults = try OneTimeCode(secret: secret)
        #expect(defaults.algorithm == .sha1 && defaults.digits == 6 && defaults.period == 30)
    }

    // MARK: Addresses

    @Test func `the example address of the key URI format is read`() throws {
        let code = try #require(OneTimeCode(uri: "otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example"))
        #expect(code.secret == Self.helloSecret)
        #expect(code.issuer == "Example")
        #expect(code.account == "alice@google.com")
        #expect(code.algorithm == .sha1 && code.digits == 6 && code.period == 30)
        #expect(code.code(at: date(59)) == "996554")
    }

    @Test func `the full example of the key URI format is written back as it was`() throws {
        let uri = "otpauth://totp/ACME%20Co:john.doe@email.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=ACME%20Co" +
            "&algorithm=SHA1&digits=6&period=30"
        let code = try #require(OneTimeCode(uri: uri))
        #expect(code.issuer == "ACME Co")
        #expect(code.account == "john.doe@email.com")
        #expect(code.secret.count == 20)
        #expect(code.uri == uri)
    }

    @Test func `the label gives the issuer unless the parameter does`() throws {
        let encoded = try #require(OneTimeCode(uri: "otpauth://totp/Big%20Corp%3A%20alice?secret=JBSWY3DPEHPK3PXP"))
        #expect(encoded.issuer == "Big Corp" && encoded.account == "alice")
        let parameter = try #require(OneTimeCode(uri: "otpauth://totp/Old:alice?secret=JBSWY3DPEHPK3PXP&issuer=New"))
        #expect(parameter.issuer == "New" && parameter.account == "alice")
        let accountOnly = try #require(OneTimeCode(uri: "otpauth://totp/alice%40example.com?secret=JBSWY3DPEHPK3PXP"))
        #expect(accountOnly.issuer == nil && accountOnly.account == "alice@example.com")
        // A QR code sometimes holds spaces left unencoded.
        let unencoded = try #require(OneTimeCode(uri: " otpauth://totp/ACME Co: john?secret=JBSW Y3DP EHPK 3PXP\n"))
        #expect(unencoded.issuer == "ACME Co" && unencoded.account == "john" && unencoded.secret == Self.helloSecret)
        let noLabel = try #require(OneTimeCode(uri: "otpauth://totp/?secret=JBSWY3DPEHPK3PXP"))
        #expect(noLabel.issuer == nil && noLabel.account == nil)
    }

    @Test func `parameters are read in any case, unknown ones ignored`() throws {
        let uri = "OTPAUTH://TOTP/GitHub:jeremy?SECRET=jbsw%20y3dp-ehpk%203pxp%3D%3D&Algorithm=sha-256&digits=8&period=60" +
            "&image=https%3A%2F%2Fexample.com%2Flogo.png&counter=4&secret=AAAA"
        let code = try #require(OneTimeCode(uri: uri))
        #expect(code.secret == Self.helloSecret)
        #expect(code.algorithm == .sha256 && code.digits == 8 && code.period == 60)
        #expect(code.issuer == "GitHub" && code.account == "jeremy")
    }

    @Test func `invalid addresses are refused with their reason`() {
        let cases: [(String, OneTimeCode.Error)] = [
            ("otpauth://hotp/Example:alice?secret=JBSWY3DPEHPK3PXP&counter=0", .counterBased),
            ("https://totp/Example:alice?secret=JBSWY3DPEHPK3PXP", .unsupportedAddress),
            ("otpauth://motp/Example:alice?secret=JBSWY3DPEHPK3PXP", .unsupportedAddress),
            ("otpauth://totp/Example:alice?issuer=Example", .missingSecret),
            ("otpauth://totp/Example:alice?secret=", .invalidSecret),
            ("otpauth://totp/Example:alice?secret=JBSWY3DP1", .invalidSecret),
            ("otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&algorithm=MD5", .unsupportedAlgorithm),
            ("otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&digits=10", .digitsOutOfRange),
            ("otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&digits=six", .digitsOutOfRange),
            ("otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&period=5", .periodOutOfRange),
        ]
        for (uri, error) in cases {
            #expect(throws: error, "\(uri)") {
                try OneTimeCode(otpauth: #require(URL(string: uri)))
            }
            #expect(OneTimeCode(uri: uri) == nil)
        }
        #expect(OneTimeCode(uri: "not an address") == nil)
    }

    @Test func `a written address reads back to the same code`() throws {
        var code = try OneTimeCode(secret: Data((0 ..< 32).map(UInt8.init)), algorithm: .sha512, digits: 7, period: 45)
        let labels: [(String?, String?)] = [
            ("Ünïcode & Co: Ltd?", "jérémy+vault@example.com"),
            (nil, "a:b"),
            ("Issuer", nil),
            (nil, nil),
            (nil, "jeremy"),
        ]
        for (issuer, account) in labels {
            code.issuer = issuer
            code.account = account
            #expect(OneTimeCode(uri: code.uri) == code, "\(code.uri)")
        }
        code.issuer = "Example"
        code.account = "alice@google.com"
        #expect(code.uri.hasPrefix("otpauth://totp/Example:alice@google.com?secret=AAAQEAYEAUDAOCAJBIFQYDIOB4IBCEQTCQKRMFYYDENBWHA5DYPQ&"))
        #expect(code.uri.hasSuffix("&issuer=Example&algorithm=SHA512&digits=7&period=45"))
    }
}
