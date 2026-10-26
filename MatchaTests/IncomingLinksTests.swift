import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Links opened by other apps (task 8.2): they wait until the app is ready, then open in a mini window or in a new
/// tab of the displayed Space, depending on the setting.
@MainActor
@Suite(.webKit)
struct IncomingLinksTests {
    private let testDefaults = TestDefaults("IncomingLinksTests")
    private let session: BrowserSession
    private let model: WindowModel
    private let manager: MiniWindowManager

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        model = WindowModel(session: session, defaults: nil)
        manager = .forTests(session: session)
    }

    @Test func `links wait until the app is ready, other schemes are ignored`() throws {
        let links = IncomingLinks()
        var opened: [[URL]] = []
        let page = try #require(URL(string: "https://example.com/article"))
        let file = URL(filePath: "/tmp/page.html")
        try links.receive([page, #require(URL(string: "mailto:moi@example.com")), file])
        #expect(opened.isEmpty)

        links.handler = { opened.append($0) }
        #expect(opened == [[page, file]])
        try links.receive([#require(URL(string: "ftp://example.com"))])
        #expect(opened.count == 1)
    }

    @Test func `each link opens in its own mini window by default`() {
        #expect(ExternalLinkDestination.current(in: testDefaults.make()) == .miniWindow)
        manager.openFromOtherApp([TestPages.url("page"), TestPages.url("autre")], destination: .miniWindow)
        #expect(manager.windows.count == 2)
        #expect(session.spaces[0].tabManager.tabs.isEmpty)
    }

    @Test func `with the setting, links open as tabs of the Space shown`() {
        let link = FakeMainWindowLink(windowModel: model)
        manager.linkMainWindow(link)
        manager.openFromOtherApp([TestPages.url("page"), TestPages.url("autre")], destination: .space)
        let tabManager = session.spaces[0].tabManager
        #expect(tabManager.todayTabs.count == 2)
        #expect(tabManager.selectedTab?.url == TestPages.url("autre"))
        #expect(link.broughtToFront == 1)
        #expect(manager.windows.isEmpty)
    }

    /// Review WB11: a local file received from another app reads only itself, unless the setting says otherwise; one
    /// chosen with ⌘O from a mini window reads its folder.
    @Test func `a local file from another app reads only itself, unless the setting says otherwise`() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "IncomingLinksTests-\(UUID().uuidString).html")
        try Data("<p>reçu</p>".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let folder = file.deletingLastPathComponent()
        manager.openMainWindow = {}
        manager.openFromOtherApp([file], destination: .space)
        manager.openFromOtherApp([file], destination: .space, isChosenByUser: true)
        let defaults = testDefaults.make()
        defaults.set(true, forKey: BrowserSettings.Key.filesFromOtherAppsReadFolder)
        let withSetting = MiniWindowManager(session: session, defaults: defaults)
        withSetting.openMainWindow = {}
        withSetting.openFromOtherApp([file], destination: .space)

        let accesses = session.spaces[0].tabManager.todayTabs.compactMap(\.fileReadAccess)
        #expect(accesses.count == 3)
        #expect(accesses.filter { $0 == file }.count == 1)
        #expect(accesses.filter { $0 == folder }.count == 2)
    }

    @Test func `with the main window closed, it opens again to show the link`() {
        var reopened = 0
        manager.openMainWindow = { reopened += 1 }
        manager.openFromOtherApp([TestPages.url("page")], destination: .space)
        #expect(reopened == 1)
        #expect(manager.pendingReveal?.tab.url == TestPages.url("page"))
    }
}
