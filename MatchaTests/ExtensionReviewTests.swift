import CryptoKit
import Foundation
@testable import Matcha
import Testing
import WebKit

/// The extensions' fixes of the review (section EX).
@MainActor
struct ExtensionReviewTests {
    /// Review EX3: a website removed in Settings isn't granted back by an update; a new grant lifts the removal.
    @Test func `an update doesn't grant back a website the user removed`() {
        var state = ExtensionState()
        state.applyRequests(permissions: [], patterns: ["*://*.example.com/*", "*://*.other.com/*"])
        state.grantedMatchPatterns["*://*.example.com/*"] = nil
        state.revokedMatchPatterns = ["*://*.example.com/*"]
        state.applyRequests(permissions: [], patterns: ["*://*.example.com/*", "*://*.other.com/*"])
        #expect(Set(state.grantedMatchPatterns.keys) == ["*://*.other.com/*"])
    }

    /// Review EX4: two bundle identifiers that give the same text never give the same extension.
    @Test func `similar bundle identifiers get different identifiers`() throws {
        let first = try #require(ExtensionIdentifier.forAppExtension(bundleIdentifier: "com.bitwarden.desktop-safari"))
        let second = try #require(ExtensionIdentifier.forAppExtension(bundleIdentifier: "com.bitwarden.desktop.safari", avoiding: [first]))
        #expect(first == "safari-com-bitwarden-desktop-safari")
        #expect(second != first && second.hasPrefix("safari-com-bitwarden-desktop-safari-"))
        #expect(ExtensionInstallDirectory.isValidIdentifier(second))
    }

    /// Review EX5: a Safari extension's data is found even once its app is gone.
    @Test func `a Safari extension keeps its identity once its app is gone`() {
        let manager = TestExtension.manager()
        var state = ExtensionState()
        state.appExtensionPath = "/Applications/Gone.app/Contents/PlugIns/Extension.appex"
        state.appExtensionIdentity = "com.example.gone.extension (ABCDE12345)"
        manager.store.setState(state, for: "safari-com-example-gone-extension")
        #expect(manager.webExtensionIdentifier(for: "safari-com-example-gone-extension") == "com.example.gone.extension (ABCDE12345)")
    }

    /// Review EX10: sync may only propose an identifier of the random form.
    @Test func `sync only proposes random identifiers`() {
        let installer = ExtensionInstaller(manager: TestExtension.manager())
        #expect(installer.placement(name: "X", publisher: nil, preferredIdentifier: "matcha-test-extension").0 != "matcha-test-extension")
        let random = ExtensionIdentifier.random()
        #expect(installer.placement(name: "X", publisher: nil, preferredIdentifier: random).0 == random)
        #expect(ExtensionIdentifier.isRandom(random) && !ExtensionIdentifier.isRandom("safari-x"))
    }

    /// Review EX13: an extension's name and badge never carry invisible characters, nor run long.
    @Test func `names and badges are cleaned`() {
        #expect(ExtensionDisplayName.cleaned("Bad\u{202E}gnp.exe") == "Badgnp.exe")
        #expect(ExtensionDisplayName.cleaned("  Two   words\n") == "Two words")
        #expect(ExtensionDisplayName.cleaned(String(repeating: "a", count: 100)).count == ExtensionDisplayName.maximumLength)
        #expect(ExtensionDisplayName.badge("12345678") == "1234")
    }

    /// Review EX14: two entries that would be the same file on disk are refused.
    @Test func `entries differing only by case or Unicode form are refused`() throws {
        let caseCollision = try ZipWriter.archive([
            (path: "manifest.json", contents: Data("{}".utf8)),
            (path: "MANIFEST.JSON", contents: Data()),
        ])
        #expect(throws: ZipArchive.Failure.unsafePath("MANIFEST.JSON")) { try ZipArchive(data: caseCollision) }
        let unicode = try ZipWriter.archive([(path: "caf\u{E9}.js", contents: Data()), (path: "cafe\u{301}.js", contents: Data())])
        #expect(throws: ZipArchive.Failure.self) { try ZipArchive(data: unicode) }
        #expect(throws: Never.self) { try ZipArchive(data: ZipWriter.archive([
            (path: "a.js", contents: Data()),
            (path: "b.js", contents: Data()),
        ])) }
    }

    /// Review EX15: a link found in the copied folder afterwards is refused.
    @Test func `a link left in the copied folder is refused`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ExtensionReviewTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ExtensionUnpacker.refuseLinks(in: folder)
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "lien"), withDestinationURL: URL(filePath: "/etc"))
        #expect(throws: ExtensionUnpacker.Failure.link) { try ExtensionUnpacker.refuseLinks(in: folder) }
    }

    /// Review EX16: a file with a proof that doesn't check out has no proven publisher, as Chrome refuses it.
    @Test func `a CRX with a false proof has no publisher`() throws {
        let developer = try CRXBuilder.Developer()
        let archive = try ZipWriter.archive([(path: "manifest.json", contents: Data("{}".utf8))])
        let signed = try CRXBuilder.crx(archive: archive, developer: developer)
        #expect(CRXSignature.verifiedPublisher(of: signed) == developer.identifier)

        let signedHeader = CRXBuilder.field(1, Data(SHA256.hash(data: developer.publicKeyInfo).prefix(16)))
        let message = Data("CRX3 SignedData\0".utf8) + LittleEndian.bytes(UInt32(signedHeader.count)) + signedHeader + archive
        let proof = try CRXBuilder.field(1, developer.publicKeyInfo) + CRXBuilder.field(2, developer.sign(message))
        let other = try CRXBuilder.Developer()
        let falseProof = CRXBuilder.field(1, other.publicKeyInfo) + CRXBuilder.field(2, Data(repeating: 1, count: 256))
        let header = CRXBuilder.field(2, proof) + CRXBuilder.field(2, falseProof) + CRXBuilder.field(10000, signedHeader)
        let file = Data("Cr24".utf8) + LittleEndian.bytes(UInt32(3)) + LittleEndian.bytes(UInt32(header.count)) + header + archive
        #expect(CRXSignature.verifiedPublisher(of: file) == nil)
    }

    /// Review EX22: an archive too large is said as such.
    @Test func `an archive too large is not called damaged`() {
        #expect(ExtensionInstallError(ZipArchive.Failure.tooLarge) == .tooLarge)
        #expect(ExtensionInstallError(ZipArchive.Failure.corrupted) == .unreadable)
    }

    /// Review EX23 and EX24: one set of limits, one reader of little-endian integers.
    @Test func `limits and integers are shared`() {
        #expect(ZipWriter.maximumEntries == ExtensionLimits.maximumEntries)
        let data = Data([0xFF, 0x34, 0x12, 0x78, 0x56])
        #expect(LittleEndian.uint16(data, at: 1) == 0x1234)
        #expect(LittleEndian.uint32(data.dropFirst(), at: 0) == 0x5678_1234)
        #expect(LittleEndian.uint32(data, at: 2) == nil)
        #expect(LittleEndian.bytes(UInt32(0x5678_1234)) == Data([0x34, 0x12, 0x78, 0x56]))
    }

    /// Review EX25: a `file:` pattern is named by itself, never by an empty host.
    @Test func `a file pattern is named by itself`() {
        #expect(InstalledExtensionRow.siteName(of: "file:///*") == "file:///*")
        #expect(InstalledExtensionRow.siteName(of: "*://*.example.com/*") == "*.example.com")
        #expect(InstalledExtensionRow.siteName(of: "<all_urls>") == nil)
    }
}
