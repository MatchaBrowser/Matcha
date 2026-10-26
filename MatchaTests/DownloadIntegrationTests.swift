import CoreServices
import Foundation
@testable import Matcha
import Testing
import WebKit

/// End-to-end downloads with real web views, without network (task 5.1): `download` link to a `data:` address,
/// local file that WebKit cannot display. The files go into a temporary folder.
@MainActor
@Suite(.webKit)
struct DownloadIntegrationTests {
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
        // The page stays displayed; nothing else opens.
        #expect(page.title == "page")
        #expect(manager.tabs.count == 1)
    }

    /// The sandbox quarantines the file written by WebKit on behalf of Matcha.
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
        // A second download without a real click (a script's) waits for the banner (audit W7); WebKit waits too.
        try await waitUntil { page.permissionPrompts.currentAction?.action == .downloadFiles }
        page.permissionPrompts.answerAction(.allowOnce)
        let items = try await waitForDownloads(2)

        #expect(items.map(\.fileName) == ["notes 2.txt", "notes.txt"])
        #expect(folder.contents() == ["notes 2.txt", "notes.txt"])
    }

    /// Response that WebKit cannot display (`canShowMIMEType` false): downloaded through the response policy.
    @Test func `file WebKit cannot show is downloaded`() async throws {
        // A file of a type WebKit can't show, written here (review TS5): never one shipped with macOS.
        let source = FileManager.default.temporaryDirectory.appending(path: "DownloadIntegrationTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: source) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let file = source.appending(path: "firmware.dfu")
        try Data(repeating: 7, count: 4096).write(to: file)
        let path = file.path
        let size = 4096

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
        // Port 1 of the local machine: connection refused immediately, without network.
        let request = try URLRequest(url: #require(URL(string: "http://127.0.0.1:1/archive.zip")))
        // Delegate attached at creation, as the coordinator does: the failure can come right after.
        let item = try await awaitCallback { done in
            page.loadedWebView.startDownload(using: request) { download in
                done(downloads.track(download, scope: .regular, pageURL: nil))
            }
        }

        try await waitUntil { !item.isActive }
        #expect(item.state == .failed)
        #expect(item.failureReason != nil)
        #expect(folder.contents().isEmpty)
    }
}
