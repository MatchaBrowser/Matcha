import Foundation
@testable import Matcha
import Testing
import WebKit

/// Termination of a page's process (task 5.7) in a session, with the window tracking of suspension (task 5.6): only
/// what is shown in an open window, in the displayed Space, reloads right away; so do the pages of mini windows. Real
/// web views, terminations reported to the delegate as WebKit does.
@MainActor
@Suite(.webKit)
struct PageCrashVisibilityTests {
    private let session: BrowserSession
    private let model: WindowModel
    private let pages = CountingTestPages()

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        model = WindowModel(session: session, defaults: nil)
        let service = session.tabLifecycle
        // No suspension during these tests: only the process termination releases a view.
        service.settings = { TabSuspensionSettings(delay: nil, checkInterval: .seconds(3600)) }
        service.listensToMemoryPressure = false
        service.windowDidAppear(model)
    }

    /// Selected tab of the displayed Space, on the local page `name`, once loaded.
    private func openTab(_ name: String) async throws -> BrowserTab {
        let tab = model.space.tabManager.insertTab(configuration: pages.configuration(), after: nil, select: true)
        tab.load(TestPages.url(name))
        try await waitUntil { tab.title == name && !tab.isLoading }
        return tab
    }

    private func terminate(_ tab: BrowserTab, in space: SpaceSession) throws {
        try space.tabManager.coordinator.webViewWebContentProcessDidTerminate(#require(tab.webView))
    }

    @Test func `every Space knows what the windows show`() {
        let added = session.addSpace(in: session.spaces[0].record.profile)
        #expect(session.spaces.allSatisfy { $0.tabManager.lifecycle === session.tabLifecycle })
        #expect(added.tabManager.lifecycle === session.tabLifecycle)
    }

    @Test func `the tab shown by the window reloads at once`() async throws {
        let tab = try await openTab("affiche")
        try terminate(tab, in: model.space)
        #expect(tab.webView != nil)
        try await waitUntil { pages.count("affiche") == 2 && !tab.crash.isRecovering && !tab.isLoading }
    }

    @Test func `the selected tab of a Space that is not shown reloads when the Space is shown`() async throws {
        let first = model.space
        let tab = try await openTab("premier")
        model.newSpace()
        // Still the tab shown by its Space, but this Space is no longer on screen.
        #expect(first.tabManager.displayedTabIDs == [tab.id])
        try terminate(tab, in: first)
        #expect(tab.webView == nil)
        #expect(tab.suspension.isSuspended)

        model.select(first)
        try await waitUntil { pages.count("premier") == 2 && tab.webView?.title == "premier" && !tab.isLoading }
    }

    @Test func `the tabs of a closed window reload when it opens again`() async throws {
        let tab = try await openTab("fenetre")
        session.tabLifecycle.windowDidDisappear(model)
        try terminate(tab, in: model.space)
        #expect(tab.webView == nil)

        // What the window does when it opens (`BrowserWindowView`).
        session.tabLifecycle.windowDidAppear(model)
        model.space.tabManager.loadSelectedTab()
        try await waitUntil { pages.count("fenetre") == 2 && tab.webView?.title == "fenetre" && !tab.isLoading }
    }

    @Test func `a mini window page is visible and reloads`() async throws {
        let minis = MiniWindowManager.forTests(session: session)
        minis.makeConfiguration = { [pages] _ in pages.configuration() }
        let mini = minis.openNew(loading: TestPages.url("mini"), source: .link)
        try await waitUntil { mini.tab.title == "mini" && !mini.tab.isLoading }
        // Main window closed: the mini window, however, is open.
        session.tabLifecycle.windowDidDisappear(model)

        let webView = try #require(mini.tab.webView)
        minis.coordinator.webViewWebContentProcessDidTerminate(webView)
        #expect(mini.tab.webView === webView)
        try await waitUntil { pages.count("mini") == 2 && !mini.tab.crash.isRecovering && !mini.tab.isLoading }
        mini.close()
    }
}
