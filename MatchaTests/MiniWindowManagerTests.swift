import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

/// Opening, command bar and closing of mini windows, with real panels (never shown) and real web views.
@MainActor
struct MiniWindowManagerTests {
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

    @Test func `a new mini window searches in the displayed Space profile, outside every Space`() {
        let second = session.addProfile(named: "Travail")
        model.select(second)
        manager.linkMainWindow(FakeMainWindowLink(windowModel: model))

        let mini = manager.openNew(source: .menu)

        #expect(mini.profileID == second.record.profile?.id)
        #expect(mini.commandBar.isPresented)
        #expect(mini.commandBar.mode == .newSearch)
        #expect(mini.commandBar.text.isEmpty)
        #expect(!mini.tab.isLoaded)
        #expect(manager.windows.map(\.id) == [mini.id])
        #expect(session.hasNoTabs)
    }

    @Test func `without a main window it uses the first Space, then the last one shown`() {
        let second = session.addProfile(named: "Travail")
        #expect(manager.openNew(source: .shortcut).profileID == session.spaces[0].record.profile?.id)

        manager.linkMainWindow(FakeMainWindowLink(windowModel: model))
        model.select(second)
        manager.unlinkMainWindow(model)

        #expect(manager.mainWindow == nil)
        #expect(manager.displayedSpace === second)
        #expect(manager.openNew(source: .shortcut).profileID == second.record.profile?.id)
    }

    @Test func `mini windows cascade from the last one opened`() {
        let first = manager.openNew(source: .menu)
        let second = manager.openNew(source: .menu)
        #expect(roughlyEqual(first.panel.frame, CGRect(x: 460, y: 123, width: 520, height: 680)))
        #expect(roughlyEqual(second.panel.frame, first.panel.frame.offsetBy(dx: 24, dy: -24)))
    }

    @Test func `a typed address loads in the mini window and touches no Space`() async throws {
        let mini = manager.openNew(source: .menu)
        let url = blankPage("tape")

        mini.commandBar.updateText(url.absoluteString)
        mini.submit(nil)

        try await waitUntil { mini.tab.url == url && !mini.tab.isLoading }
        #expect(!mini.commandBar.isPresented)
        #expect(mini.container.webView === mini.tab.webView)
        #expect(mini.tab.webView?.superview === mini.container)
        #expect(session.hasNoTabs)
    }

    @Test func `escape closes an empty mini window and keeps one with a page`() async throws {
        let empty = manager.openNew(source: .menu)
        empty.cancelCommandBar()
        try await waitUntil { manager.windows.isEmpty }

        let mini = try await openPage("page")
        mini.showCommandBar(.editAddress)
        #expect(mini.commandBar.mode == .editAddress)
        mini.cancelCommandBar()
        #expect(!mini.commandBar.isPresented)
        #expect(manager.windows.map(\.id) == [mini.id])
    }

    @Test func `escape reaching the panel closes only an empty mini window`() async throws {
        let mini = try await openPage("page")
        mini.panel.cancelOperation(nil)
        #expect(manager.windows.count == 1)

        let empty = manager.openNew(source: .menu)
        empty.commandBar.dismiss()
        empty.panel.cancelOperation(nil)
        try await waitUntil { manager.windows.map(\.id) == [mini.id] }
    }

    @Test func `command W closes the bar first, then the window`() async throws {
        let mini = try await openPage("page")
        mini.showCommandBar(.newSearch)

        mini.closeCommand()
        #expect(!mini.commandBar.isPresented)
        #expect(manager.windows.count == 1)

        mini.closeCommand()
        try await waitUntil { manager.windows.isEmpty }
    }

    @Test func `closing frees the web view and touches no Space`() async throws {
        let mini = try await openPage("page")
        let webView = try #require(mini.tab.webView)

        mini.close()

        try await waitUntil { manager.windows.isEmpty }
        #expect(!mini.tab.isLoaded)
        #expect(webView.superview == nil)
        #expect(mini.container.webView == nil)
        #expect(session.spaces[0].tabManager.tabs.isEmpty)
    }

    @Test func `deleting a profile closes only its mini windows`() async throws {
        let second = session.addProfile(named: "Travail")
        manager.linkMainWindow(FakeMainWindowLink(windowModel: model))
        model.select(second)
        let work = manager.openNew(source: .menu)
        model.selectSpace(at: 0)
        let personal = manager.openNew(source: .menu)

        try manager.closeWindows(ofProfile: #require(second.record.profile?.id))

        try await waitUntil { manager.windows.map(\.id) == [personal.id] }
        #expect(!work.tab.isLoaded)
    }

    @Test func `the key mini window is followed for the menus`() async throws {
        let first = manager.openNew(source: .menu)
        let second = manager.openNew(source: .menu)

        manager.keyChanged(first, isKey: true)
        #expect(manager.keyWindowID == first.id)
        manager.keyChanged(second, isKey: false)
        #expect(manager.keyWindowID == first.id)
        first.close()
        try await waitUntil { manager.keyWindowID == nil && manager.windows.count == 1 }
    }
}
