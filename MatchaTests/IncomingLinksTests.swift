import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Liens ouverts par d'autres apps (tâche 8.2) : ils attendent que l'app soit prête, puis s'ouvrent dans une
/// mini-fenêtre ou dans un nouvel onglet du Space affiché, selon le réglage.
@MainActor
struct IncomingLinksTests {
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

    @Test func `each link opens in its own mini window by default`() throws {
        #expect(try ExternalLinkDestination
            .current(in: #require(UserDefaults(suiteName: "IncomingLinks-\(UUID().uuidString)"))) == .miniWindow)
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

    @Test func `with the main window closed, it opens again to show the link`() {
        var reopened = 0
        manager.openMainWindow = { reopened += 1 }
        manager.openFromOtherApp([TestPages.url("page")], destination: .space)
        #expect(reopened == 1)
        #expect(manager.pendingReveal?.tab.url == TestPages.url("page"))
    }
}
