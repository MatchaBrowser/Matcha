import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

/// « Ouvrir dans le Space » : la page d'une mini-fenêtre passe dans un Space et la fenêtre principale la montre.
@MainActor
struct MiniWindowOpenInSpaceTests {
    private let session: BrowserSession
    private let model: WindowModel
    private let manager: MiniWindowManager

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        model = WindowModel(session: session, defaults: nil)
        manager = .forTests(session: session)
    }

    /// Mini-fenêtre ouverte sur la page locale `name`, une fois chargée.
    private func openPage(_ name: String) async throws -> MiniWindowController {
        let mini = manager.openNew(loading: TestPages.url(name), source: .link)
        try await waitUntil { mini.tab.title == name && !mini.tab.isLoading }
        return mini
    }

    @Test func `open in Space moves the same web view without reloading`() async throws {
        let link = FakeMainWindowLink(windowModel: model)
        manager.linkMainWindow(link)
        let mini = try await openPage("page")
        let webView = try #require(mini.tab.webView)
        _ = try await webView.evaluateJavaScript("window.marker = 42; true")
        var reopened = 0

        manager.openInSpace(mini) { reopened += 1 }

        let tabManager = session.spaces[0].tabManager
        #expect(tabManager.selectedTab === mini.tab)
        #expect(tabManager.todayTabs.first === mini.tab)
        #expect(mini.tab.webView === webView)
        #expect(webView.superview == nil)
        #expect(webView.navigationDelegate === tabManager.coordinator)
        #expect(link.broughtToFront == 1)
        #expect(reopened == 0)
        try await waitUntil { manager.windows.isEmpty }
        // La fermeture de la mini-fenêtre ne libère pas la page remise.
        #expect(mini.tab.webView === webView)
        let marker = try await webView.evaluateJavaScript("window.marker")
        #expect(marker as? Int == 42)
    }

    @Test func `a second open in Space does nothing`() async throws {
        manager.linkMainWindow(FakeMainWindowLink(windowModel: model))
        let mini = try await openPage("page")

        manager.openInSpace(mini) {}
        manager.openInSpace(mini) {}

        #expect(session.spaces[0].tabManager.tabs.map(\.id) == [mini.tab.id])
    }

    @Test func `the target follows the displayed Space of the same profile`() async throws {
        let link = FakeMainWindowLink(windowModel: model)
        manager.linkMainWindow(link)
        let mini = try await openPage("page")
        model.newSpace()
        let second = model.space
        #expect(manager.defaultTarget(profileID: mini.profileID) === second)

        // Space d'un autre profil affiché : le premier Space du profil de la page, et la fenêtre y passe.
        model.select(session.addProfile(named: "Travail"))
        #expect(manager.defaultTarget(profileID: mini.profileID) === session.spaces[0])
        manager.openInSpace(mini) {}

        #expect(model.space === session.spaces[0])
        #expect(session.spaces[0].tabManager.selectedTab === mini.tab)
        #expect(second.tabManager.tabs.isEmpty)
        #expect(link.broughtToFront == 1)
    }

    @Test func `a closed main window is reopened and then shows the page`() async throws {
        let mini = try await openPage("page")
        var reopened = 0

        manager.openInSpace(mini) { reopened += 1 }

        #expect(reopened == 1)
        #expect(session.spaces[0].tabManager.selectedTab === mini.tab)
        // La fenêtre rouverte affiche un autre Space : le lien la ramène sur celui de la page.
        model.newSpace()
        manager.linkMainWindow(FakeMainWindowLink(windowModel: model))
        #expect(model.space === session.spaces[0])
        #expect(manager.pendingReveal == nil)
    }

    @Test func `without a Space of its profile the page reopens from its address in the displayed Space`() async throws {
        manager.linkMainWindow(FakeMainWindowLink(windowModel: model))
        let work = session.addProfile(named: "Travail")
        model.select(work)
        let url = blankPage("travail")
        let mini = manager.openNew(loading: url, source: .link)
        try await waitUntil { mini.tab.url == url && !mini.tab.isLoading }
        model.deleteSpace(work)
        #expect(model.space === session.spaces[0])

        manager.openInSpace(mini) {}

        let moved = try #require(session.spaces[0].tabManager.selectedTab)
        #expect(moved !== mini.tab)
        #expect(!mini.tab.isLoaded)
        try await waitUntil { moved.url == url && manager.windows.isEmpty }
    }
}
