import CryptoKit
import Foundation
@testable import Matcha
import Testing

/// Publisher of a CRX3 file (audit E1): only a signature that checks out names it.
struct CRXSignatureTests {
    private let archive = Data("PK\u{3}\u{4} une archive".utf8)

    @Test func `a file signed by its developer names that developer`() throws {
        let developer = try CRXBuilder.Developer()
        let file = try CRXBuilder.crx(archive: archive, developer: developer)
        let publisher = try #require(CRXSignature.verifiedPublisher(of: file))
        #expect(publisher == developer.identifier)
        #expect(publisher.count == 32)
        #expect(publisher.allSatisfy { ("a" ... "p").contains($0) })
    }

    @Test func `a changed archive or a borrowed identity names no one`() throws {
        let developer = try CRXBuilder.Developer()
        let impostor = try CRXBuilder.Developer()
        let tampered = try CRXBuilder.crx(archive: archive, developer: developer, tamperedArchive: archive + Data("!".utf8))
        #expect(CRXSignature.verifiedPublisher(of: tampered) == nil)
        // The impostor claims the developer's key, but can't sign with it.
        let borrowed = try CRXBuilder.crx(archive: archive, developer: impostor, claimedKey: developer.publicKeyInfo)
        #expect(CRXSignature.verifiedPublisher(of: borrowed) == nil)
    }

    @Test func `an ecdsa signature checks out too`() throws {
        let key = P256.Signing.PrivateKey()
        let file = try CRXBuilder.ecdsaCRX(archive: archive, key: key)
        #expect(CRXSignature.verifiedPublisher(of: file) != nil)
    }

    @Test func `other formats and malformed headers name no one`() {
        #expect(CRXSignature.verifiedPublisher(of: archive) == nil)
        #expect(CRXSignature.verifiedPublisher(of: Data("Cr24".utf8) + Data([3, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0x7F])) == nil)
        #expect(CRXSignature.verifiedPublisher(of: Data("Cr24".utf8) + Data([2, 0, 0, 0, 4, 0, 0, 0, 1, 2, 3, 4])) == nil)
        #expect(ProtobufFields([0x0A, 0x05, 0x01]) == nil)
    }
}
