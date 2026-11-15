import Foundation
@testable import Matcha
import Testing

/// SSH keys between OpenSSH and PKCS#8 (`VAULT.md` § 9.4): keys of `ssh-keygen`, PKCS#8 of Python `cryptography`, the
/// RSA key of the CXF example.
struct VaultSSHKeyTests {
    private typealias Fixtures = VaultImportFixtures

    @Test func `keys in the OpenSSH format give the public key and fingerprint of ssh-keygen`() throws {
        let ed25519 = try #require(VaultSSHKey(text: Fixtures.ed25519OpenSSH))
        #expect(ed25519.keyType == "ssh-ed25519")
        #expect(ed25519.comment == "test@ed25519")
        #expect(ed25519.publicKey == Fixtures.ed25519Public)
        #expect(ed25519.fingerprint == Fixtures.ed25519Fingerprint)
        let p256 = try #require(VaultSSHKey(text: Fixtures.p256OpenSSH))
        #expect(p256.keyType == "ecdsa-sha2-nistp256")
        #expect(p256.publicKey == Fixtures.p256Public)
        #expect(p256.fingerprint == Fixtures.p256Fingerprint)
    }

    @Test func `keys convert both ways between OpenSSH and PKCS#8`() throws {
        let ed25519 = try #require(VaultSSHKey(text: Fixtures.ed25519OpenSSH))
        #expect(ed25519.pkcs8 == Fixtures.base64(Fixtures.ed25519PKCS8))
        #expect(VaultSSHKey(pkcs8: Fixtures.base64(Fixtures.ed25519PKCS8), comment: "test@ed25519") == ed25519)
        let p256 = try #require(VaultSSHKey(text: Fixtures.p256OpenSSH))
        #expect(VaultSSHKey(pkcs8: Fixtures.base64(Fixtures.p256PKCS8), comment: "test@p256") == p256)
        #expect(try VaultSSHKey(pkcs8: #require(p256.pkcs8), comment: "test@p256") == p256)
        // OpenSSH written here, read here and by the format's rules: the same key.
        #expect(VaultSSHKey(text: ed25519.openSSH) == ed25519)
        #expect(VaultSSHKey(text: p256.openSSH) == p256)
        #expect(VaultSSHKey(text: Fixtures.ed25519OpenSSH)?.openSSH == ed25519.openSSH)
    }

    @Test func `an RSA key gets back the exact PKCS#8 it came from`() throws {
        let der = try #require(VaultCXFSchema.data(base64URL: Fixtures.rsaPKCS8))
        let rsa = try #require(VaultSSHKey(pkcs8: der, comment: ""))
        #expect(rsa.keyType == "ssh-rsa")
        #expect(rsa.fingerprint == Fixtures.rsaFingerprint)
        let reread = try #require(VaultSSHKey(text: rsa.openSSH))
        // The CRT exponents are computed again from d, p and q.
        #expect(reread.pkcs8 == der)
    }

    @Test func `a PEM PKCS#8 key is read`() throws {
        let pem = "-----BEGIN PRIVATE KEY-----\n\(Fixtures.ed25519PKCS8)\n-----END PRIVATE KEY-----\n"
        let key = try #require(VaultSSHKey(text: pem, comment: "laptop"))
        #expect(key.comment == "laptop")
        #expect(key.fingerprint == Fixtures.ed25519Fingerprint)
    }

    @Test func `other formats, encrypted or damaged keys are not read`() {
        #expect(VaultSSHKey(text: "-----BEGIN RSA PRIVATE KEY-----\nAAAA\n-----END RSA PRIVATE KEY-----") == nil)
        #expect(VaultSSHKey(text: "not a key") == nil)
        #expect(VaultSSHKey(text: "") == nil)
        let encrypted = Data("openssh-key-v1\0".utf8) + VaultSSHEncoding.string("aes256-ctr")
        let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n\(encrypted.base64EncodedString())\n-----END OPENSSH PRIVATE KEY-----"
        #expect(VaultSSHKey(text: pem) == nil)
        var damaged = Fixtures.base64(Fixtures.ed25519PKCS8)
        damaged.removeLast()
        #expect(VaultSSHKey(pkcs8: damaged, comment: "") == nil)
        #expect(VaultSSHKey(pkcs8: Data([0x30, 0x84, 0xFF, 0xFF, 0xFF, 0xFF]), comment: "") == nil)
    }

    @Test func `big integers subtract one and reduce`() {
        #expect(VaultSSHEncoding.minusOne([0x01, 0x00]) == [0xFF])
        #expect(VaultSSHEncoding.minusOne([0x00]) == nil)
        #expect(VaultSSHEncoding.remainder([0x01, 0x00, 0x01], modulo: [0x01, 0x00]) == [0x01])
        #expect(VaultSSHEncoding.remainder([0xFF, 0xFF, 0xFF, 0xFF, 0xFF], modulo: [0x07]) == [0x01])
        #expect(VaultSSHEncoding.remainder([0x05], modulo: [0x09]) == [0x05])
        #expect(VaultSSHEncoding.remainder([0x05], modulo: []) == nil)
    }
}
