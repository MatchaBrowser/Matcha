import Foundation
@testable import Matcha
import Testing
import WebKit

/// Local pages received from another app (review WB11): one that refers to files next to it, which it can't read,
/// gets the banner; “Open…” lets it read its folder. Real web views, pages written in a temporary folder.
@MainActor
@Suite(.webKit)
struct PageLocalFilesTests {
    /// A folder with a page that shows its image, a page alone, and the image; removed with it.
    @MainActor
    private final class Folder {
        let url = FileManager.default.temporaryDirectory.appending(path: "PageLocalFilesTests-\(UUID().uuidString)")
        let withImage: URL
        let alone: URL

        init() throws {
            withImage = url.appending(path: "photo.html")
            alone = url.appending(path: "seule.html")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let png = try #require(AvatarImage.initials("M", color: "#0A84FF"))
            try png.write(to: url.appending(path: "photo.png"))
            try Data("<title>photo</title><img src=\"photo.png\"><a href=\"seule.html\">seule</a>".utf8).write(to: withImage)
            try Data("<title>seule</title><p>Rien d'autre.</p><a href=\"photo.html\">photo</a>".utf8).write(to: alone)
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let folder: Folder

    init() throws {
        folder = try Folder()
    }

    @Test func `a page from another app that refers to its images shows the banner, until it is chosen again`() async throws {
        let tab = manager.newTab(url: folder.withImage, isFromAnotherApp: true)
        try await waitUntil { tab.localFiles.hasUnreadableNeighbors }
        #expect(tab.fileReadAccess == folder.withImage)

        // “Open…”: the file chosen again reads its folder, and the banner goes.
        let finished = tab.history.finishedLoads
        tab.openChosenFile(folder.withImage)
        try await waitUntil { tab.history.finishedLoads > finished && !tab.isLoading }
        #expect(tab.fileReadAccess == folder.withImage.deletingLastPathComponent())
        #expect(!tab.localFiles.hasUnreadableNeighbors)
    }

    @Test func `a page from another app without other files shows no banner`() async throws {
        let tab = manager.newTab(url: folder.alone, isFromAnotherApp: true)
        try await waitUntil { tab.localFiles.answers == 1 }
        #expect(!tab.localFiles.hasUnreadableNeighbors)
    }

    @Test func `a page that reads its folder shows no banner`() async throws {
        let tab = manager.newTab(url: folder.withImage)
        try await waitUntil { tab.history.finishedLoads == 1 && !tab.isLoading }
        #expect(tab.fileReadAccess == folder.withImage.deletingLastPathComponent())
        #expect(!tab.localFiles.hasUnreadableNeighbors)
        #expect(tab.localFiles.answers == 0)
    }

    @Test func `a closed banner stays closed for its document`() async throws {
        let tab = manager.newTab(url: folder.withImage, isFromAnotherApp: true)
        try await waitUntil { tab.localFiles.hasUnreadableNeighbors }
        tab.localFiles.dismiss()
        #expect(!tab.localFiles.hasUnreadableNeighbors)
    }

    @Test func `files from other apps read only themselves unless the setting says otherwise`() {
        #expect(!BrowserSettings.filesFromOtherAppsReadFolder)
        let testDefaults = TestDefaults("PageLocalFilesTests")
        let defaults = testDefaults.make()
        #expect(!BrowserSettings.readsFolderOfFilesFromOtherApps(in: defaults))
        defaults.set(true, forKey: BrowserSettings.Key.filesFromOtherAppsReadFolder)
        #expect(BrowserSettings.readsFolderOfFilesFromOtherApps(in: defaults))
    }
}
