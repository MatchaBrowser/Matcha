import CryptoKit
import Foundation
@testable import Matcha
import Testing

/// An `openssh-key-v1` file whose fields the tests change one at a time.
private struct OpenSSHFile {
    var cipher = "none"
    var kdf = "none"
    var kdfOptions: [UInt8] = []
    var keyCount: UInt32 = 1
    var publicBlob: [UInt8]
    var section: [UInt8]

    /// The file of `key`, with `checkInts` and the padding `padding` (1, 2, 3… by default).
    init(key: SSHPrivateKey, checkInts: (UInt32, UInt32) = (7, 7), padding: UInt8 = 1) {
        publicBlob = key.publicBlob
        var writer = SSHWireWriter()
        writer.write(checkInts.0)
        writer.write(checkInts.1)
        key.writePrivate(to: &writer)
        writer.write(string: "comment")
        var next = padding
        while writer.bytes.count % 8 != 0 {
            writer.write(byte: next)
            next &+= 1
        }
        section = writer.bytes
    }

    var text: String {
        var writer = SSHWireWriter()
        writer.write(raw: Array("openssh-key-v1\0".utf8))
        writer.write(string: cipher)
        writer.write(string: kdf)
        writer.write(string: kdfOptions)
        writer.write(keyCount)
        writer.write(string: publicBlob)
        writer.write(string: section)
        return SSHKeyMalformedTests.armored("OPENSSH PRIVATE KEY", writer.bytes)
    }
}

/// Damaged or hostile key files (`VAULT.md` § 9.4): an `SSHKeyError`, never a crash, and never an inconsistent key.
struct SSHKeyMalformedTests {
    private let key = SSHPrivateKey.ed25519(Curve25519.Signing.PrivateKey())

    static func armored(_ label: String, _ body: [UInt8]) -> String {
        "-----BEGIN \(label)-----\n" + Data(body).base64EncodedString(options: .lineLength64Characters)
            + "\n-----END \(label)-----\n"
    }

    private func body(of fixture: SSHKeyFixture) throws -> SSHPEMBlock {
        try #require(try SSHPEMBlock.firstPrivateKey(in: fixture.text))
    }

    @Test(arguments: SSHKeyFixtures.unencrypted + SSHKeyFixtures.pem)
    func `a truncated key is refused`(fixture: SSHKeyFixture) throws {
        let block = try body(of: fixture)
        for length in 0 ..< block.body.count {
            let text = Self.armored(block.label, Array(block.body.prefix(length)))
            #expect(throws: SSHKeyError.self) { try SSHKeyImporter.importKey(text, passphrase: nil) }
        }
    }

    /// Every damaged copy of `fixture` that can be imported, one byte changed at a time.
    private func damagedKeys(of fixture: SSHKeyFixture) throws -> [SSHKey] {
        let block = try body(of: fixture)
        let step = max(1, block.body.count / 120)
        return stride(from: 0, to: block.body.count, by: step).flatMap { position in
            [0x01, 0x80, 0xFF].compactMap { (mask: UInt8) in
                var damaged = block.body
                damaged[position] ^= mask
                return try? SSHKeyImporter.importKey(Self.armored(block.label, damaged), passphrase: nil)
            }
        }
    }

    /// OpenSSH's format repeats the public key, and so do these PEM files of ECDSA keys: only the comment, and RSA's
    /// private exponent and coefficient, can change unseen, never what's derived from the public key.
    @Test(arguments: SSHKeyFixtures.unencrypted + [
        SSHKeyFixtures.p256SEC1, SSHKeyFixtures.p384PKCS8, SSHKeyFixtures.p256SEC1Named, SSHKeyFixtures.p256PKCS8Named,
    ])
    func `a damaged key is refused or keeps its fingerprint`(fixture: SSHKeyFixture) throws {
        for key in try damagedKeys(of: fixture) {
            #expect(key.fingerprint == fixture.fingerprint)
        }
    }

    /// Ed25519 in PKCS#8 and RSA in PKCS#1 don't repeat the public key (nor RSA's public exponent): as with
    /// `ssh-keygen`, a damaged file can give another key, but always a valid one.
    @Test(arguments: [SSHKeyFixtures.ed25519PKCS8, SSHKeyFixtures.rsa2048PKCS1, SSHKeyFixtures.rsa2048PKCS8])
    func `a damaged PEM key is refused or gives a valid key`(fixture: SSHKeyFixture) throws {
        for key in try damagedKeys(of: fixture) {
            #expect(try SSHKeyImporter.importKey(key.privateKey, passphrase: nil) == key)
        }
    }

    @Test func `random bytes are refused`() {
        var generator = SplitMix64(seed: 2026)
        let labels = ["OPENSSH PRIVATE KEY", "PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY"]
        let prefixes: [[UInt8]] = [[], Array("openssh-key-v1\0".utf8), [0x30, 0x82, 0x01, 0x00], [0x30, 0x84, 0xFF, 0xFF, 0xFF, 0xFF]]
        for _ in 0 ..< 400 {
            let length = Int.random(in: 0 ..< 600, using: &generator)
            let noise = (0 ..< length).map { _ in UInt8.random(in: 0 ... 255, using: &generator) }
            let prefix = prefixes.randomElement(using: &generator) ?? []
            let text = Self.armored(labels.randomElement(using: &generator) ?? "", prefix + noise)
            #expect(throws: SSHKeyError.self) { try SSHKeyImporter.importKey(text, passphrase: "correct horse") }
        }
    }

    @Test func `text that isn't a key or is too large is refused`() {
        let fixture = SSHKeyFixtures.ed25519
        let texts = [
            "",
            "not a key",
            "-----BEGIN OPENSSH PRIVATE KEY-----\n-----END OPENSSH PRIVATE KEY-----\n",
            fixture.text.replacing("-----END OPENSSH PRIVATE KEY-----", with: ""),
            fixture.text.replacing("b3BlbnNzaC1", with: "b3BlbnNzaC!"),
            fixture.text + String(repeating: " ", count: SSHKeyImporter.maximumTextSize),
        ]
        for text in texts {
            #expect(throws: SSHKeyError.malformed) { try SSHKeyImporter.importKey(text, passphrase: nil) }
        }
    }

    @Test func `the header of an OpenSSH file is checked`() {
        #expect(throws: Never.self) { try SSHKeyImporter.importKey(OpenSSHFile(key: key).text, passphrase: nil) }
        var file = OpenSSHFile(key: key)
        file.keyCount = 0
        #expect(throws: SSHKeyError.malformed) { try SSHKeyImporter.importKey(file.text, passphrase: nil) }
        file.keyCount = 2
        #expect(throws: SSHKeyError.unsupported(.multipleKeys)) { try SSHKeyImporter.importKey(file.text, passphrase: nil) }
        file = OpenSSHFile(key: key)
        file.kdf = "scrypt"
        #expect(throws: SSHKeyError.unsupported(.kdf("scrypt"))) { try SSHKeyImporter.importKey(file.text, passphrase: nil) }
        file.kdf = "none"
        file.cipher = "aes256-ctr"
        #expect(throws: SSHKeyError.malformed) { try SSHKeyImporter.importKey(file.text, passphrase: nil) }
        file.cipher = "none"
        file.kdfOptions = [0]
        #expect(throws: SSHKeyError.malformed) { try SSHKeyImporter.importKey(file.text, passphrase: nil) }
        file = OpenSSHFile(key: key)
        file.publicBlob[file.publicBlob.count - 1] ^= 1
        #expect(throws: SSHKeyError.malformed) { try SSHKeyImporter.importKey(file.text, passphrase: nil) }
        file.publicBlob = SSHPrivateKey.ed25519(Curve25519.Signing.PrivateKey()).publicBlob
        #expect(throws: SSHKeyError.malformed) { try SSHKeyImporter.importKey(file.text, passphrase: nil) }
    }

    @Test func `the bcrypt cost is checked before the passphrase is asked for`() {
        var file = OpenSSHFile(key: key)
        file.cipher = "aes256-ctr"
        file.kdf = "bcrypt"
        var options = SSHWireWriter()
        options.write(string: Array(repeating: 1, count: 16))
        options.write(UInt32(5000))
        file.kdfOptions = options.bytes
        #expect(throws: SSHKeyError.unsupported(.kdfRounds(5000))) { try SSHKeyImporter.importKey(file.text, passphrase: nil) }
        options = SSHWireWriter()
        options.write(string: Array(repeating: 1, count: 16))
        options.write(UInt32(0))
        file.kdfOptions = options.bytes
        #expect(throws: SSHKeyError.malformed) { try SSHKeyImporter.importKey(file.text, passphrase: "correct horse") }
        file.kdfOptions = []
        #expect(throws: SSHKeyError.malformed) { try SSHKeyImporter.importKey(file.text, passphrase: "correct horse") }
    }

    @Test func `the private section is checked`() {
        let mismatched = OpenSSHFile(key: key, checkInts: (7, 8))
        #expect(throws: SSHKeyError.malformed) { try SSHKeyImporter.importKey(mismatched.text, passphrase: nil) }
        let padding = OpenSSHFile(key: key, padding: 2)
        #expect(throws: SSHKeyError.malformed) { try SSHKeyImporter.importKey(padding.text, passphrase: nil) }
        var unknown = OpenSSHFile(key: key)
        var writer = SSHWireWriter()
        writer.write(string: "sk-ssh-ed25519@openssh.com")
        writer.write(string: Array(repeating: 0, count: 32))
        unknown.publicBlob = writer.bytes
        let expected = SSHKeyError.unsupported(.keyType("sk-ssh-ed25519@openssh.com"))
        #expect(throws: expected) { try SSHKeyImporter.importKey(unknown.text, passphrase: nil) }
    }

    @Test func `the readers refuse lengths beyond the data`() {
        var wire = SSHWireReader([0xFF, 0xFF, 0xFF, 0xFF, 1, 2])
        #expect(throws: SSHKeyError.malformed) { try wire.readString() }
        var negative = SSHWireReader([0, 0, 0, 1, 0x80])
        #expect(throws: SSHKeyError.malformed) { try negative.readMPInt() }
        let hostile: [[UInt8]] = [
            [0x30, 0x85, 1, 0, 0, 0, 0], // a 5-byte length
            [0x30, 0x80, 0, 0], // an indefinite length
            [0x30, 0x84, 0x7F, 0xFF, 0xFF, 0xFF, 0], // a length beyond the data
            [0x30, 0x03, 0x02, 0x01, 0x80], // a negative integer
        ]
        for bytes in hostile {
            #expect(throws: SSHKeyError.self) { try SSHRSAKey(pkcs1: bytes) }
            #expect(throws: SSHKeyError.self) { try SSHPEMKeyDecoder.pkcs8(bytes) }
            #expect(throws: SSHKeyError.self) { try SSHPEMKeyDecoder.sec1(bytes, curve: nil) }
        }
    }
}

/// A seeded generator, so that the random inputs are the same on every run.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
