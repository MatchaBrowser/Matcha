import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

/// “Open in Space”: the page of a mini window moves into a Space and the main window shows it.
@MainActor
@Suite(.webKit)
struct MiniWindowOpenInSpaceTests {
    private let session: BrowserSession
    private let model: WindowModel
    private let manager: MiniWindowManager

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        model = WindowModel(session: session, defaults: nil)
        manager = .forTests(session: session)
    }

    /// Mini window opened on the local page `name`, once loaded.
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
        // Closing the mini window does not release the handed-over page.
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

        // Space of another profile displayed: the first Space of the page's profile, and the window switches to it.
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
        // The reopened window displays another Space: the link brings it back to the page's Space.
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
