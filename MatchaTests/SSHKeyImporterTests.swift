import Foundation
@testable import Matcha
import Testing

/// Import of SSH keys into the vault (`VAULT.md` § 9.4): files written by `ssh-keygen` and OpenSSL
/// (`SSHKeyFixtures`), whose public line and fingerprint must be those `ssh-keygen` gives, kept unencrypted in
/// OpenSSH's format.
struct SSHKeyImporterTests {
    private func expectMatches(_ key: SSHKey, _ fixture: SSHKeyFixture) {
        #expect(key.publicKey == fixture.publicKey)
        #expect(key.fingerprint == fixture.fingerprint)
        #expect(key.bits == fixture.bits)
        #expect(key.keyType.rawValue == String(fixture.publicKey.prefix { $0 != " " }))
    }

    @Test(arguments: SSHKeyFixtures.unencrypted)
    func `an OpenSSH key gives ssh-keygen's public key and fingerprint`(fixture: SSHKeyFixture) throws {
        let key = try SSHKeyImporter.importKey(fixture.text, passphrase: nil)
        expectMatches(key, fixture)
        #expect(key.comment == fixture.publicKey.split(separator: " ").dropFirst(2).joined(separator: " "))
        // Same check numbers, same layout: the vault keeps the file byte for byte as ssh-keygen wrote it.
        #expect(key.privateKey == fixture.text + "\n")
    }

    @Test(arguments: SSHKeyFixtures.encrypted)
    func `an encrypted OpenSSH key is decrypted with its passphrase and kept unencrypted`(fixture: SSHKeyFixture) throws {
        let key = try SSHKeyImporter.importKey(fixture.text, passphrase: fixture.passphrase)
        expectMatches(key, fixture)
        #expect(key.privateKey.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQ"))
        #expect(try SSHKeyImporter.importKey(key.privateKey, passphrase: nil) == key)
    }

    @Test(arguments: SSHKeyFixtures.encrypted)
    func `a wrong or missing passphrase is reported as such`(fixture: SSHKeyFixture) {
        #expect(throws: SSHKeyError.wrongPassphrase) { try SSHKeyImporter.importKey(fixture.text, passphrase: "correct horse!") }
        #expect(throws: SSHKeyError.needsPassphrase) { try SSHKeyImporter.importKey(fixture.text, passphrase: nil) }
        #expect(throws: SSHKeyError.needsPassphrase) { try SSHKeyImporter.importKey(fixture.text, passphrase: "") }
    }

    @Test(arguments: SSHKeyFixtures.pem)
    func `a PEM key gives ssh-keygen's public key and fingerprint`(fixture: SSHKeyFixture) throws {
        let key = try SSHKeyImporter.importKey(fixture.text, passphrase: nil)
        expectMatches(key, fixture)
        #expect(key.comment.isEmpty)
        #expect(key.privateKey.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----\n"))
        #expect(try SSHKeyImporter.importKey(key.privateKey, passphrase: nil) == key)
    }

    @Test func `a key converted by ssh-keygen keeps its fingerprint`() throws {
        let pairs: [(SSHKeyFixture, SSHKeyFixture)] = [
            (SSHKeyFixtures.p256, SSHKeyFixtures.p256SEC1),
            (SSHKeyFixtures.p384, SSHKeyFixtures.p384PKCS8),
            (SSHKeyFixtures.p256SEC1Named, SSHKeyFixtures.p256PKCS8Named),
            (SSHKeyFixtures.rsa2048PKCS1, SSHKeyFixtures.rsa2048PKCS8),
        ]
        for (original, converted) in pairs {
            let first = try SSHKeyImporter.importKey(original.text, passphrase: nil)
            let second = try SSHKeyImporter.importKey(converted.text, passphrase: nil)
            #expect(first.fingerprint == second.fingerprint)
        }
    }

    @Test func `a key surrounded by other text, indented or with CRLF line breaks is found`() throws {
        let fixture = SSHKeyFixtures.ed25519
        let crlf = fixture.text.replacing("\n", with: "\r\n")
        let indented = fixture.text.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n")
        for text in ["Key for the server:\n\n" + fixture.text + "\n\n-- \nSent from my Mac\n", crlf, indented] {
            #expect(try SSHKeyImporter.importKey(text, passphrase: nil).fingerprint == fixture.fingerprint)
        }
        // ssh-keygen's EC files may start with the curve's parameters, which are skipped.
        let parameters = "-----BEGIN EC PARAMETERS-----\nBggqhkjOPQMBBw==\n-----END EC PARAMETERS-----\n"
        let named = SSHKeyFixtures.p256SEC1Named
        #expect(try SSHKeyImporter.importKey(parameters + named.text, passphrase: nil).fingerprint == named.fingerprint)
    }

    @Test func `weak RSA keys and encrypted PEM files are refused`() {
        #expect(throws: SSHKeyError.weakRSA) { try SSHKeyImporter.importKey(SSHKeyFixtures.rsa1024PKCS8.text, passphrase: nil) }
        for fixture in [SSHKeyFixtures.p256EncryptedPEM, SSHKeyFixtures.p256EncryptedPKCS8] {
            #expect(throws: SSHKeyError.encryptedPEM) { try SSHKeyImporter.importKey(fixture.text, passphrase: "correct horse") }
        }
    }

    @Test func `what isn't a supported private key says what it is`() {
        let chacha = SSHKeyFixtures.ed25519ChaCha20
        #expect(throws: SSHKeyError.unsupported(.cipher("chacha20-poly1305@openssh.com"))) {
            try SSHKeyImporter.importKey(chacha.text, passphrase: chacha.passphrase)
        }
        let publicKeys = [
            SSHKeyFixtures.ed25519.publicKey,
            SSHKeyFixtures.rsa3072.publicKey,
            "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAkLt2uAETx+5dPUluBEsVg1wHYFtg02xQ2HThCMIsxG8=\n-----END PUBLIC KEY-----\n",
            "---- BEGIN SSH2 PUBLIC KEY ----\nComment: \"256-bit ED25519\"\nAAAAC3NzaC1lZDI1NTE5AAAAIA==\n---- END SSH2 PUBLIC KEY ----\n",
        ]
        for text in publicKeys {
            #expect(throws: SSHKeyError.unsupported(.publicKey)) { try SSHKeyImporter.importKey(text, passphrase: nil) }
        }
        let otherFormats = [
            "PuTTY-User-Key-File-3: ssh-ed25519\nEncryption: none\nComment: putty\n",
            "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n",
            "---- BEGIN SSH2 ENCRYPTED PRIVATE KEY ----\nP2/56wAAAA==\n---- END SSH2 ENCRYPTED PRIVATE KEY ----\n",
        ]
        for text in otherFormats {
            #expect(throws: SSHKeyError.unsupported(.format)) { try SSHKeyImporter.importKey(text, passphrase: nil) }
        }
        let dsa = "-----BEGIN DSA PRIVATE KEY-----\nMAA=\n-----END DSA PRIVATE KEY-----\n"
        #expect(throws: SSHKeyError.unsupported(.keyType("ssh-dss"))) { try SSHKeyImporter.importKey(dsa, passphrase: nil) }
        // PKCS#8 X25519 (RFC 8410): a key, but not for SSH.
        let x25519 = "-----BEGIN PRIVATE KEY-----\n" + "MC4CAQAwBQYDK2VuBCIEIHBvbmllcyBhcmUgbm90IGtleXMgYnV0IGFsbW9zdCEh\n"
            + "-----END PRIVATE KEY-----\n"
        #expect(throws: SSHKeyError.unsupported(.keyType("1.3.101.110"))) { try SSHKeyImporter.importKey(x25519, passphrase: nil) }
    }
}
