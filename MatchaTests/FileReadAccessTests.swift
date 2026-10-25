import Foundation
@testable import Matcha
import Testing
import WebKit

/// What a local page may read (audit W6): its folder when the user opens it, never more than the linking page's; the
/// file alone when another app sends it, links resolved, and the tab keeps it (review WB11).
struct FileReadAccessTests {
    private let file = URL(filePath: "/Users/moi/Documents/docs/guide/page.html")

    @Test func `a file the user opens reads its folder`() {
        #expect(FileReadAccess.readableURL(for: file, openedFrom: nil) == file.deletingLastPathComponent())
    }

    @Test func `a file linked from a website only reads itself`() {
        let website = URL(string: "https://example.com/")
        #expect(FileReadAccess.readableURL(for: file, openedFrom: website) == file)
    }

    @Test(arguments: [
        ("/Users/moi/Documents/docs/guide/index.html", true),
        ("/Users/moi/Documents/docs/index.html", true),
        ("/Users/moi/Documents/docs/guide/../index.html", true),
        ("/Users/moi/Documents/docs/guide/plus/index.html", false),
        ("/Users/moi/Documents/doc/index.html", false),
        ("/Users/moi/Downloads/piege.html", false),
    ])
    func `a file linked from a local page reads its folder only inside that page's`(source: String, readsFolder: Bool) {
        let readable = FileReadAccess.readableURL(for: file, openedFrom: URL(filePath: source))
        #expect(readable == (readsFolder ? file.deletingLastPathComponent() : file))
    }

    @Test func `a file received from another app only reads itself`() {
        #expect(FileReadAccess.readableURL(for: file, openedFrom: nil, isFromAnotherApp: true) == file)
    }

    @Test func `a link to a folder elsewhere doesn't pass for a folder inside the page's`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FileReadAccessTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "site")
        let elsewhere = root.appending(path: "ailleurs")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: source.appending(path: "lien"), withDestinationURL: elsewhere)

        let linked = source.appending(path: "lien/page.html")
        #expect(FileReadAccess.readableURL(for: linked, openedFrom: source.appending(path: "index.html")) == linked)
        let inside = source.appending(path: "guide/page.html")
        #expect(FileReadAccess.readableURL(for: inside, openedFrom: source.appending(path: "index.html")) == inside
            .deletingLastPathComponent())
        #expect(FileReadAccess.covers(source, inside))
        #expect(!FileReadAccess.covers(source, linked))
        #expect(!FileReadAccess.covers(source.appending(path: "guide/autre.html"), inside))
    }

    @Test @MainActor func `a tab keeps the access granted to its file, after an unload and a relaunch`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "FileReadAccessTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let page = folder.appending(path: "recu.html")
        try Data("<p>reçu</p>".utf8).write(to: page)
        let configuration = WebConfigurationFactory().makeConfiguration(websiteDataStore: .nonPersistent())
        let tab = BrowserTab(configuration: configuration)
        tab.load(page, isFromAnotherApp: true)
        #expect(tab.fileReadAccess == page)

        tab.unload(resettingTo: page, title: nil)
        _ = tab.loadedWebView
        #expect(tab.fileReadAccess == page)

        let stored = StoredTab(id: UUID(), url: page, lastActivity: .now, fileReadAccess: tab.fileReadAccess)
        let restored = BrowserTab(restoring: stored, configuration: configuration)
        _ = restored.loadedWebView
        #expect(restored.fileReadAccess == page)
    }
}
