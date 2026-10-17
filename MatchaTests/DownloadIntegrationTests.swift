import CoreServices
import Foundation
@testable import Matcha
import Testing
import WebKit

/// Téléchargements de bout en bout avec de vraies vues web, sans réseau (tâche 5.1) : lien `download` vers une
/// adresse `data:`, fichier local que WebKit ne sait pas afficher. Les fichiers vont dans un dossier temporaire.
@MainActor
struct DownloadIntegrationTests {
    /// Fichiers livrés avec macOS que WebKit n'affiche pas (le premier présent sert) ; le test d'interface utilise les
    /// mêmes.
    static let undisplayableFiles = [
        "/usr/share/firmware/bluetooth/20702_8289.dfu",
        "/usr/share/man/man1/less.1.gz",
        "/usr/share/tokenizer/th/matrix.bin",
    ]

    private let manager: TabManager
    private let folder: TemporaryDownloadsFolder
    private let downloads: DownloadManager

    init() throws {
        try self.init(scope: .regular)
    }

    private init(scope: DownloadScope) throws {
        manager = TabManager(websiteDataStore: .nonPersistent(), downloadScope: scope)
        folder = try TemporaryDownloadsFolder()
        downloads = folder.makeManager()
        manager.coordinator.downloadManager = downloads
    }

    private func openPage(body: String) async throws -> BrowserTab {
        let page = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        page.load(TestPages.url("page", body: body))
        try await waitUntil { page.title == "page" && !page.isLoading }
        return page
    }

    private func click(_ id: String, in page: BrowserTab) async throws {
        _ = try await page.loadedWebView.evaluateJavaScript("document.getElementById('\(id)').click(); true")
    }

    private func waitForDownloads(_ count: Int) async throws -> [DownloadItem] {
        try await waitUntil { downloads.items.count == count && downloads.items.allSatisfy { !$0.isActive } }
        return downloads.items
    }

    @Test func `download link saves the file under its suggested name`() async throws {
        let page = try await openPage(body: "<a id='l' download='notes.txt' href='data:text/plain,bonjour'>notes</a>")

        try await click("l", in: page)
        let item = try #require(try await waitForDownloads(1).first)

        #expect(item.state == .finished)
        #expect(item.fileName == "notes.txt")
        #expect(item.completedBytes == 7)
        #expect(item.scope == .regular)
        #expect(folder.contents() == ["notes.txt"])
        #expect(try String(contentsOf: folder.url.appendingPathComponent("notes.txt"), encoding: .utf8) == "bonjour")
        // La page reste affichée ; rien d'autre ne s'ouvre.
        #expect(page.title == "page")
        #expect(manager.tabs.count == 1)
    }

    /// La sandbox met le fichier écrit par WebKit en quarantaine au nom de Matcha.
    @Test func `downloaded file is quarantined`() async throws {
        let page = try await openPage(body: "<a id='l' download='script.command' href='data:text/plain,echo'>script</a>")

        try await click("l", in: page)
        let item = try #require(try await waitForDownloads(1).first)

        let destination = try #require(item.destinationURL)
        let properties = try #require(DownloadQuarantine.currentProperties(of: destination))
        #expect(properties[kLSQuarantineAgentNameKey as String] as? String == DownloadQuarantine.agentName)
        var buffer = [CChar](repeating: 0, count: 256)
        #expect(getxattr(destination.path, "com.apple.quarantine", &buffer, buffer.count, 0, 0) > 0)
    }

    @Test func `same name twice gives a numbered copy`() async throws {
        let page = try await openPage(body: "<a id='l' download='notes.txt' href='data:text/plain,bonjour'>notes</a>")

        try await click("l", in: page)
        _ = try await waitForDownloads(1)
        try await click("l", in: page)
        let items = try await waitForDownloads(2)

        #expect(items.map(\.fileName) == ["notes 2.txt", "notes.txt"])
        #expect(folder.contents() == ["notes 2.txt", "notes.txt"])
    }

    /// Réponse que WebKit ne sait pas afficher (`canShowMIMEType` faux) : téléchargée par la politique de réponse.
    @Test func `file WebKit cannot show is downloaded`() async throws {
        let path = try #require(Self.undisplayableFiles.first(where: FileManager.default.isReadableFile(atPath:)))
        let size = try #require(try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int)

        manager.newTab(url: URL(fileURLWithPath: path))
        let item = try #require(try await waitForDownloads(1).first)

        #expect(item.state == .finished)
        #expect(item.fileName == URL(fileURLWithPath: path).lastPathComponent)
        #expect(item.completedBytes == Int64(size))
        #expect(item.sourceURL == URL(fileURLWithPath: path))
        #expect(folder.contents() == [item.fileName])
    }

    @Test func `downloads of a private window belong to it`() async throws {
        let scope = DownloadScope.privateWindow(UUID())
        let test = try Self(scope: scope)
        let page = try await test.openPage(body: "<a id='l' download='privé.txt' href='data:text/plain,chut'>privé</a>")

        try await test.click("l", in: page)
        let item = try #require(try await test.waitForDownloads(1).first)

        #expect(item.scope == scope)
        #expect(test.downloads.items(in: .regular).isEmpty)
        test.downloads.forgetDownloads(in: scope)
        #expect(test.downloads.items.isEmpty)
        #expect(test.folder.contents() == ["privé.txt"])
    }

    @Test func `failed download keeps no file`() async throws {
        let page = try await openPage(body: "")
        // Port 1 de la machine : connexion refusée aussitôt, sans réseau.
        let request = try URLRequest(url: #require(URL(string: "http://127.0.0.1:1/archive.zip")))
        // Délégué branché dès la création, comme le fait le coordinateur : l'échec peut arriver aussitôt après.
        let item = await withCheckedContinuation { continuation in
            page.loadedWebView.startDownload(using: request) { download in
                continuation.resume(returning: downloads.track(download, scope: .regular, pageURL: nil))
            }
        }

        try await waitUntil { !item.isActive }
        #expect(item.state == .failed)
        #expect(item.failureReason != nil)
        #expect(folder.contents().isEmpty)
    }
}
