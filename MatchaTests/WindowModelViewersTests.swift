import Foundation
@testable import Matcha
import Testing
import WebKit

/// Several browser windows on one session: each on its Space and its tab, the sidebar being the same.
@MainActor
struct WindowModelViewersTests {
    private let session: BrowserSession
    private let first: WindowModel

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        first = WindowModel(session: session, defaults: nil)
        first.windowDidAppear()
    }

    private var tabManager: TabManager {
        session.spaces[0].tabManager
    }

    /// A second window, displayed, on `spaceID` (the last displayed Space without it).
    private func openSecondWindow(on spaceID: UUID? = nil) -> WindowModel {
        let second = WindowModel(session: session, defaults: nil, spaceID: spaceID)
        second.windowDidAppear()
        return second
    }

    @Test func `a new window on the same Space starts without a tab and keeps its own selection`() {
        let tab = tabManager.newTab()
        let second = openSecondWindow()
        #expect(second.space === first.space)
        #expect(second.selectedTab == nil)
        second.activate()
        let other = tabManager.newTab()
        #expect(second.selectedTab === other)
        #expect(first.selectedTab === tab)
    }

    @Test func `a window coming to the front receives the tab actions`() {
        tabManager.newTab()
        let second = openSecondWindow()
        second.windowDidBecomeKey()
        #expect(tabManager.activeViewer === second.viewer)
        first.windowDidBecomeKey()
        #expect(tabManager.activeViewer === first.viewer)
    }

    @Test func `a window showing a Space again takes back its tab`() {
        let tab = tabManager.newTab()
        let home = first.space
        first.newSpace()
        let second = openSecondWindow(on: home.id)
        #expect(second.selectedTab === tab)
        #expect(tabManager.shows(tab.id, in: second.viewer))
        first.select(home)
        #expect(tabManager.shows(tab.id, in: first.viewer))
        #expect(!tabManager.shows(tab.id, in: second.viewer))
    }

    @Test func `a closed window releases its viewers and leaves the actions to the other`() {
        let second = openSecondWindow()
        second.activate()
        second.windowDidClose()
        #expect(tabManager.viewers.all.count == 1)
        #expect(tabManager.activeViewer === first.viewer)
    }

    @Test func `a window whose Space is deleted elsewhere shows the first Space`() {
        first.newSpace()
        let deleted = first.space
        let second = openSecondWindow(on: deleted.id)
        first.selectSpace(at: 0)
        first.deleteSpace(deleted)
        second.spacesDidChange()
        #expect(second.space === session.spaces[0])
        #expect(second.currentSpaceID == session.spaces[0].id)
    }

    @Test func `each window makes visible the tabs it displays`() {
        let tab = tabManager.newTab()
        let second = openSecondWindow()
        second.activate()
        let other = tabManager.newTab()
        #expect(first.visibleTabIDs == [tab.id])
        #expect(second.visibleTabIDs == [other.id])
    }

    @Test func `extensions see each tab in one window only`() throws {
        let tab = tabManager.newTab()
        let background = tabManager.newTab(select: false)
        let second = openSecondWindow()
        second.activate()
        let other = tabManager.newTab()
        let windows = ExtensionWindows()
        windows.windowDidAppear(first, window: nil)
        windows.windowDidAppear(second, window: nil)
        windows.update(beforeLoading: true)
        let firstID = try #require(windows.adapter(for: first)?.windowID)
        let secondID = try #require(windows.adapter(for: second)?.windowID)
        #expect(Set(windows.tabs(inWindow: firstID).map(\.tabID)) == [tab.id, background.id])
        #expect(windows.tabs(inWindow: secondID).map(\.tabID) == [other.id])
        #expect(windows.activeTab(inWindow: secondID)?.tabID == other.id)
    }

    @Test func `mini windows follow the last active window, then the previous one`() {
        let miniWindows = MiniWindowManager.forTests(session: session)
        let second = openSecondWindow()
        miniWindows.linkMainWindow(FakeMainWindowLink(windowModel: first))
        miniWindows.linkMainWindow(FakeMainWindowLink(windowModel: second))
        #expect(miniWindows.mainWindow?.windowModel === second)
        miniWindows.linkMainWindow(FakeMainWindowLink(windowModel: first))
        #expect(miniWindows.mainWindow?.windowModel === first)
        miniWindows.unlinkMainWindow(first)
        #expect(miniWindows.mainWindow?.windowModel === second)
    }

    /// Review ON13: a window opened in the background by a page goes to the window that shows the page; it is never
    /// selected in another window showing the Space.
    @Test func `a window opened in the background by a page is never selected in another window`() throws {
        let tab = tabManager.newTab()
        let second = openSecondWindow()
        second.activate()
        #expect(second.selectedTab == nil)
        let webView = try #require(tab.webView)
        _ = tabManager.openWindow(configuration: webView.configuration, from: webView, inBackground: true)
        #expect(second.selectedTab == nil)
        #expect(first.selectedTab === tab)
        #expect(tabManager.todayTabs.count == 2)
    }
}
