import Foundation
@testable import Matcha
import Testing

/// Liste des téléchargements, noms réservés, annulation, « Effacer », fenêtres privées (tâche 5.1). Les éléments sont
/// créés sans objet WebKit ; le parcours réel est couvert par `DownloadIntegrationTests`.
@MainActor
struct DownloadManagerTests {
    private let folder: TemporaryDownloadsFolder
    private let downloads: DownloadManager
    private let privateScope = DownloadScope.privateWindow(UUID())

    init() throws {
        folder = try TemporaryDownloadsFolder()
        downloads = folder.makeManager()
    }

    private func item(_ name: String = "rapport.pdf", scope: DownloadScope = .regular) -> DownloadItem {
        let item = DownloadItem(download: nil, scope: scope, sourceURL: URL(string: "https://example.com/\(name)"), pageURL: nil)
        downloads.insert(item)
        return item
    }

    private func reserve(_ item: DownloadItem, suggested: String = "rapport.pdf") -> URL? {
        let response = URLResponse(url: item.sourceURL!, mimeType: "application/pdf", expectedContentLength: 10, textEncodingName: nil)
        return downloads.reserveDestination(for: item, suggestedFilename: suggested, response: response)
    }

    @Test func `newest downloads come first`() {
        let first = item("a.zip")
        let second = item("b.zip")
        #expect(downloads.items.map(\.id) == [second.id, first.id])
        #expect(first.fileName == "a.zip")
        #expect(first.isActive)
    }

    @Test func `destination is a free name in the folder`() throws {
        try Data().write(to: folder.url.appendingPathComponent("rapport.pdf"))
        let download = item()

        let destination = try #require(reserve(download))
        #expect(destination == folder.url.appendingPathComponent("rapport 2.pdf"))
        #expect(download.destinationURL == destination)
        #expect(download.fileName == "rapport 2.pdf")
    }

    /// WebKit n'a pas encore créé le premier fichier quand le second choisit sa place.
    @Test func `simultaneous downloads never share a name`() throws {
        let first = try #require(reserve(item()))
        let second = try #require(reserve(item()))
        let third = try #require(reserve(item(), suggested: "RAPPORT.PDF"))
        #expect(first.lastPathComponent == "rapport.pdf")
        #expect(second.lastPathComponent == "rapport 2.pdf")
        #expect(third.lastPathComponent == "RAPPORT 3.PDF")
    }

    @Test func `a missing folder is created`() throws {
        let nested = folder.url.appendingPathComponent("Téléchargements", isDirectory: true)
        let manager = DownloadManager(directory: { nested })
        let download = DownloadItem(download: nil, scope: .regular, sourceURL: URL(string: "https://example.com/a.zip"), pageURL: nil)
        manager.insert(download)
        let response = try URLResponse(url: #require(download.sourceURL), mimeType: nil, expectedContentLength: -1, textEncodingName: nil)

        let destination = try #require(manager.reserveDestination(for: download, suggestedFilename: "a.zip", response: response))
        #expect(destination.deletingLastPathComponent().standardizedFileURL == nested.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: nested.path))
    }

    @Test func `no folder means no destination`() throws {
        let manager = DownloadManager(directory: { nil })
        let download = DownloadItem(download: nil, scope: .regular, sourceURL: nil, pageURL: nil)
        let response = try URLResponse(
            url: #require(URL(string: "https://example.com/a.zip")),
            mimeType: nil,
            expectedContentLength: -1,
            textEncodingName: nil,
        )
        #expect(manager.reserveDestination(for: download, suggestedFilename: "a.zip", response: response) == nil)
    }

    @Test func `cancelling removes the partial file and frees its name`() throws {
        let download = item()
        let destination = try #require(reserve(download))
        try Data("partiel".utf8).write(to: destination)

        downloads.cancel(download)

        #expect(download.state == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(downloads.items.contains { $0 === download })
        #expect(reserve(item()) == destination)
    }

    @Test func `cancelling a finished download does nothing`() throws {
        let download = item()
        let destination = try #require(reserve(download))
        try Data("fini".utf8).write(to: destination)
        download.markFinished(size: 4)

        downloads.cancel(download)

        #expect(download.state == .finished)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func `clear removes what is over in this window only, never files`() throws {
        let finished = item("fini.zip")
        let destination = try #require(reserve(finished, suggested: "fini.zip"))
        try Data().write(to: destination)
        finished.markFinished(size: 0)
        let failed = item("raté.zip")
        failed.markFailed(reason: nil)
        let running = item("encours.zip")
        let other = item("privé.zip", scope: privateScope)
        other.markFinished(size: 0)

        downloads.clear(in: .regular)

        #expect(downloads.items.map(\.id) == [other.id, running.id])
        #expect(downloads.items(in: .regular).map(\.id) == [running.id])
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func `closing a private window cancels and forgets its downloads`() throws {
        let finished = item("fini.zip", scope: privateScope)
        let finishedFile = try #require(reserve(finished, suggested: "fini.zip"))
        try Data().write(to: finishedFile)
        finished.markFinished(size: 0)
        downloads.recordFinish(in: privateScope)
        let running = item("encours.zip", scope: privateScope)
        let partialFile = try #require(reserve(running, suggested: "encours.zip"))
        try Data().write(to: partialFile)
        let regular = item("normal.zip")

        downloads.forgetDownloads(in: privateScope)

        #expect(downloads.items.map(\.id) == [regular.id])
        #expect(running.state == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: partialFile.path))
        #expect(FileManager.default.fileExists(atPath: finishedFile.path))
        #expect(downloads.finishedCount(in: privateScope) == 0)
    }

    @Test func `progress summary`() {
        #expect(DownloadProgressSummary.fraction(completed: 5, total: 10) == 0.5)
        #expect(DownloadProgressSummary.fraction(completed: 15, total: 10) == 1)
        #expect(DownloadProgressSummary.fraction(completed: 5, total: nil) == nil)
        #expect(DownloadProgressSummary.fraction(completed: 0, total: 0) == nil)
        #expect(DownloadProgressSummary.overallFraction(of: [(10, 40), (30, 60)]) == 0.4)
        #expect(DownloadProgressSummary.overallFraction(of: [(10, 40), (30, nil)]) == nil)
        #expect(DownloadProgressSummary.overallFraction(of: []) == nil)
    }
}
