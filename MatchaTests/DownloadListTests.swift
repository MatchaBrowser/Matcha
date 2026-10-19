import Foundation
@testable import Matcha
import Testing

/// Download list kept from one launch to the next: ordinary windows only, until “Clear”; deleted or moved file
/// reported as missing.
@MainActor
struct DownloadListTests {
    private let folder: TemporaryDownloadsFolder
    private let defaults: UserDefaults

    init() throws {
        folder = try TemporaryDownloadsFolder()
        let name = "DownloadListTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
    }

    /// Manager “launched” on the test's settings: it picks up the saved list.
    private func launch() -> DownloadManager {
        let downloads = folder.makeManager()
        downloads.restoreList(from: defaults)
        return downloads
    }

    private func item(_ name: String, in downloads: DownloadManager, scope: DownloadScope = .regular) -> DownloadItem {
        let item = DownloadItem(download: nil, scope: scope, sourceURL: URL(string: "https://example.com/\(name)"), pageURL: nil)
        downloads.insert(item)
        return item
    }

    /// Finished download, with its file of `size` bytes in the test folder.
    private func finishedItem(_ name: String, in downloads: DownloadManager, scope: DownloadScope = .regular) throws -> DownloadItem {
        let item = item(name, in: downloads, scope: scope)
        let destination = folder.url.appendingPathComponent(name)
        try Data(count: 12).write(to: destination)
        item.setDestination(destination)
        item.markFinished(size: 12)
        return item
    }

    private func saved(_ id: UUID, outcome: SavedDownload.Outcome = .finished) -> SavedDownload {
        SavedDownload(id: id, fileName: "\(id).zip", fileURL: nil, outcome: outcome, byteCount: 1, failureReason: nil)
    }

    // MARK: Saved list (pure type)

    @Test func `the saved list keeps its order and its most recent entries`() {
        let entries = (0 ..< SavedDownloadList.limit + 5).map { _ in saved(UUID()) }
        SavedDownloadList.save(entries, to: defaults)
        #expect(SavedDownloadList.load(from: defaults) == Array(entries.prefix(SavedDownloadList.limit)))
    }

    @Test func `an empty list removes the saved value`() {
        SavedDownloadList.save([saved(UUID())], to: defaults)
        SavedDownloadList.save([], to: defaults)
        #expect(defaults.object(forKey: SavedDownloadList.defaultsKey) == nil)
        #expect(SavedDownloadList.load(from: defaults).isEmpty)
    }

    @Test func `an unreadable saved value gives an empty list`() {
        defaults.set(Data("pas du JSON".utf8), forKey: SavedDownloadList.defaultsKey)
        #expect(SavedDownloadList.load(from: defaults).isEmpty)
    }

    // MARK: From one launch to the next

    @Test func `downloads of regular windows that are over come back at the next launch`() throws {
        let downloads = launch()
        let finished = try finishedItem("rapport.pdf", in: downloads)
        let failed = item("raté.zip", in: downloads)
        failed.markFailed(reason: "Connexion perdue")
        let cancelled = item("annulé.zip", in: downloads)
        downloads.cancel(cancelled)
        _ = item("encours.zip", in: downloads)
        _ = try finishedItem("privé.zip", in: downloads, scope: .privateWindow(UUID()))
        downloads.saveList()

        let relaunched = launch()

        #expect(relaunched.items.map(\.id) == [cancelled.id, failed.id, finished.id])
        let restored = try #require(relaunched.items.last)
        #expect(restored.scope == .regular)
        #expect(restored.state == .finished)
        #expect(restored.fileName == "rapport.pdf")
        #expect(restored.destinationURL == finished.destinationURL)
        #expect(restored.completedBytes == 12)
        #expect(restored.totalBytes == 12)
        #expect(!restored.isFileMissing)
        #expect(relaunched.items[1].state == .failed)
        #expect(relaunched.items[1].failureReason == "Connexion perdue")
        #expect(relaunched.items[0].state == .cancelled)
        // Nothing makes the button bounce at launch.
        #expect(relaunched.finishedCount(in: .regular) == 0)
    }

    @Test func `a download still running when the app quits comes back as failed`() throws {
        let downloads = launch()
        let running = item("encours.zip", in: downloads)
        downloads.saveList(includingActive: true)

        let restored = try #require(launch().items.first)

        #expect(restored.id == running.id)
        #expect(restored.state == .failed)
        #expect(restored.failureReason?.isEmpty == false)
    }

    @Test func `clear empties the saved list, other windows aside`() throws {
        let downloads = launch()
        _ = try finishedItem("rapport.pdf", in: downloads)
        downloads.saveList()
        let relaunched = launch()
        #expect(relaunched.items.count == 1)

        relaunched.clear(in: .regular)

        #expect(SavedDownloadList.load(from: defaults).isEmpty)
        #expect(launch().items.isEmpty)
    }

    @Test func `without saved settings nothing is written`() throws {
        let downloads = folder.makeManager()
        _ = try finishedItem("rapport.pdf", in: downloads)
        downloads.saveList()
        #expect(launch().items.isEmpty)
    }

    // MARK: Missing file

    @Test func `a deleted or moved file is missing`() throws {
        let downloads = launch()
        let finished = try finishedItem("rapport.pdf", in: downloads)
        let running = item("encours.zip", in: downloads)
        #expect(!finished.isFileMissing)
        #expect(!running.isFileMissing)

        try FileManager.default.removeItem(at: #require(finished.destinationURL))

        #expect(finished.isFileMissing)
        let withoutFile = item("perdu.zip", in: downloads)
        withoutFile.markFinished(size: 0)
        #expect(withoutFile.isFileMissing)
    }
}
