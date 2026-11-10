import Foundation
@testable import Matcha
import Testing

/// Generation of the vault's SSH keys (`VAULT.md` § 9.4): written in OpenSSH's format as `ssh-keygen` writes it, and
/// read back unchanged. That `ssh-keygen` reads them and signs with them was checked by hand, for each type.
struct SSHKeyGeneratorTests {
    private func expectWellFormed(_ key: SSHKey, type: SSHKeyType, comment: String) throws {
        #expect(key.keyType == type)
        let fields = key.publicKey.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        #expect(fields.first == type.rawValue)
        #expect(fields.dropFirst(2).joined(separator: " ") == comment)
        #expect(key.comment == comment)
        // SHA-256 is 32 bytes: 43 characters of base 64 once the padding is removed.
        #expect(key.fingerprint.hasPrefix("SHA256:") && key.fingerprint.count == 50 && !key.fingerprint.hasSuffix("="))
        let lines = key.privateKey.split(separator: "\n")
        #expect(lines.first == "-----BEGIN OPENSSH PRIVATE KEY-----" && lines.last == "-----END OPENSSH PRIVATE KEY-----")
        #expect(lines.dropFirst().dropLast().allSatisfy { $0.count <= 70 })
        #expect(key.privateKey.hasSuffix("-----\n"))
        #expect(try SSHKeyImporter.importKey(key.privateKey, passphrase: nil) == key)
    }

    @Test(arguments: [SSHKeyType.ed25519, .ecdsaP256, .ecdsaP384])
    func `a generated key reads back the same`(type: SSHKeyType) throws {
        let key = try SSHKeyGenerator.generate(type, comment: "jeremy@matcha")
        try expectWellFormed(key, type: type, comment: "jeremy@matcha")
        #expect(key.bits == nil)
        #expect(try SSHKeyGenerator.generate(type, comment: "jeremy@matcha").fingerprint != key.fingerprint)
    }

    @Test func `an RSA key has the size asked for and reads back the same`() throws {
        let key = try SSHKeyGenerator.generate(.rsa, rsaBits: 3072, comment: "")
        try expectWellFormed(key, type: .rsa, comment: "")
        #expect(key.bits == 3072)
        #expect(!key.publicKey.hasSuffix(" "))
    }

    @Test func `only 3072 and 4096-bit RSA keys are generated`() {
        for bits in [1024, 2048, 3000, 8192] {
            #expect(throws: SSHKeyError.invalidRSASize) { try SSHKeyGenerator.generate(.rsa, rsaBits: bits, comment: "") }
        }
    }

    @Test func `the comment stays on a single line`() throws {
        let key = try SSHKeyGenerator.generate(.ed25519, comment: "line one\nline two\r\tend\u{2028}é")
        #expect(key.comment == "line one line two  end é")
        #expect(key.publicKey.hasSuffix(" line one line two  end é"))
        let lines = key.publicKey.split(whereSeparator: \.isNewline)
        #expect(lines.count == 1)
    }
}
