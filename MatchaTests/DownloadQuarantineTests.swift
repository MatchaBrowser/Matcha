import CoreServices
import Foundation
@testable import Matcha
import Testing

/// Propriétés de quarantaine des fichiers téléchargés (tâche 5.1). Le comportement réel (attribut posé par la
/// sandbox sur le fichier écrit par WebKit) est vérifié par `DownloadIntegrationTests` et le test d'interface.
struct DownloadQuarantineTests {
    private static let agent = kLSQuarantineAgentNameKey as String
    private static let type = kLSQuarantineTypeKey as String
    private static let dataURL = kLSQuarantineDataURLKey as String
    private static let originURL = kLSQuarantineOriginURLKey as String
    private static let bundle = kLSQuarantineAgentBundleIdentifierKey as String

    @Test func `properties name the app, the file and its page`() {
        let properties = DownloadQuarantine.properties(
            sourceURL: URL(string: "https://cdn.example.com/app.dmg?token=1"),
            pageURL: URL(string: "https://example.com/telecharger"),
            agentName: "Matcha",
            bundleIdentifier: "com.matchabrowser.matcha",
        )
        #expect(properties[Self.agent] as? String == "Matcha")
        #expect(properties[Self.bundle] as? String == "com.matchabrowser.matcha")
        #expect(properties[Self.type] as? String == kLSQuarantineTypeWebDownload as String)
        #expect(properties[Self.dataURL] as? URL == URL(string: "https://cdn.example.com/app.dmg?token=1"))
        #expect(properties[Self.originURL] as? URL == URL(string: "https://example.com/telecharger"))
    }

    @Test func `only web addresses are recorded, without credentials`() {
        #expect(DownloadQuarantine
            .recordedURL(URL(string: "https://moi:secret@example.com/a.zip")) == URL(string: "https://example.com/a.zip"))
        #expect(DownloadQuarantine.recordedURL(URL(string: "HTTP://example.com/a.zip")) != nil)
        #expect(DownloadQuarantine.recordedURL(URL(string: "data:application/zip;base64,UEsDBA==")) == nil)
        #expect(DownloadQuarantine.recordedURL(URL(string: "blob:https://example.com/0f3e")) == nil)
        #expect(DownloadQuarantine.recordedURL(URL(fileURLWithPath: "/usr/share/a.bin")) == nil)
        #expect(DownloadQuarantine.recordedURL(nil) == nil)
    }

    /// Fichier créé par l'app (sandboxée) : la sandbox le met en quarantaine d'elle-même, rien n'est réécrit.
    @Test func `a file created in the sandbox is already quarantined`() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Quarantine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("fichier.bin")
        try Data("abc".utf8).write(to: file)

        let properties = try #require(DownloadQuarantine.currentProperties(of: file))
        #expect(properties[Self.agent] as? String == DownloadQuarantine.agentName)
        #expect(DownloadQuarantine.ensure(on: file, properties: [Self.agent: "Autre"]) == .alreadyQuarantined)
        #expect(DownloadQuarantine.currentProperties(of: file)?[Self.agent] as? String == DownloadQuarantine.agentName)
    }

    @Test func `a missing file cannot be quarantined`() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID().uuidString).bin")
        #expect(DownloadQuarantine.ensure(on: file, properties: [Self.agent: "Matcha"]) == .failed)
    }
}
