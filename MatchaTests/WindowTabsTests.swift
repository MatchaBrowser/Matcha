import Foundation
@testable import Matcha
import Testing
import WebKit

/// A tab dragged out of the sidebar: a window of its own tabs, outside any Space (Arc's “This Window”).
@MainActor
struct WindowTabsTests {
    private let session: BrowserSession
    private let first: WindowModel

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        first = WindowModel(session: session, defaults: nil)
        first.windowDidAppear()
    }

    private var space: SpaceSession {
        session.spaces[0]
    }

    /// The window opened by `state`, displayed.
    private func open(_ state: BrowserWindowState) -> WindowModel {
        let window = WindowModels(session: session, spaceID: state.spaceID, windowTabsID: state.windowTabsID).window
        window.windowDidAppear()
        return window
    }

    @Test func `a detached tab leaves the Space for a window of its own`() throws {
        let below = space.tabManager.newTab()
        let tab = space.tabManager.newTab()
        let state = first.detachToNewWindow(tab)
        #expect(first.selectedTab === below)
        #expect(space.tabManager.tab(withID: tab.id) == nil)
        let window = open(state)
        let tabs = try #require(window.windowTabs)
        #expect(window.space === space)
        #expect(tabs.tabManager.tabs.map(\.id) == [tab.id])
        #expect(window.selectedTab === tab)
        #expect(window.tabManager.shows(tab.id, in: window.viewer))
    }

    @Test func `a pinned tab stays in the sidebar and the new window gets a copy`() {
        let pinned = space.tabManager.newTab(url: URL(string: "about:blank"))
        space.tabManager.setPlace(pinned, to: .pinned)
        let window = open(first.detachToNewWindow(pinned))
        #expect(space.tabManager.place(of: pinned) == .pinned)
        #expect(window.tabManager.tabs.count == 1)
        #expect(window.selectedTab !== pinned)
    }

    @Test func `new tabs of the window stay in it`() {
        let tab = space.tabManager.newTab()
        let window = open(first.detachToNewWindow(tab))
        window.activate()
        window.tabManager.newTab()
        #expect(window.tabManager.tabs.count == 2)
        #expect(space.tabManager.tabs.isEmpty)
    }

    @Test func `move to gives the tabs to a Space and the window shows it`() {
        let tab = space.tabManager.newTab()
        let window = open(first.detachToNewWindow(tab))
        window.moveWindowTabs(to: space)
        #expect(window.windowTabs == nil)
        #expect(session.windowTabs.isEmpty)
        #expect(space.tabManager.place(of: tab) == .today)
        #expect(window.selectedTab === tab)
        #expect(space.tabManager.shows(tab.id, in: window.viewer))
    }

    @Test func `closing the window closes its tabs, which the Space can reopen`() {
        let tab = space.tabManager.newTab(url: URL(string: "about:blank"))
        let window = open(first.detachToNewWindow(tab))
        window.windowDidClose()
        #expect(session.windowTabs.isEmpty)
        #expect(space.tabManager.tab(withID: tab.id) == nil)
        #expect(space.tabManager.closedTabs.lastCount == 1)
    }

    @Test func `quitting puts the tabs back in their Space`() {
        let tab = space.tabManager.newTab()
        _ = open(first.detachToNewWindow(tab))
        session.returnWindowTabs()
        #expect(session.windowTabs.isEmpty)
        #expect(space.tabManager.place(of: tab) == .today)
    }

    /// Review ON5: the Space the tabs came from is deleted while their window is open.
    @Test func `when their Space is deleted, the tabs go back to the first Space of their profile`() throws {
        let other = session.addSpace(inProfileOf: space)
        let window = open(BrowserWindowState(spaceID: other.id))
        let tab = other.tabManager.newTab()
        let detached = open(window.detachToNewWindow(tab))
        let tabs = try #require(detached.windowTabs)
        session.deleteSpace(other)
        #expect(session.originSpace(of: tabs) === space)

        session.returnWindowTabs()
        #expect(session.windowTabs.isEmpty)
        // Same profile: the same tab, moved, not recreated.
        #expect(space.tabManager.tab(withID: tab.id) === tab)
        #expect(space.tabManager.place(of: tab) == .today)
    }

    /// Review ON5: closing the window of a deleted Space still lets ⇧⌘T bring its tabs back.
    @Test func `when their Space is deleted, closing the window keeps its tabs for reopening`() {
        let other = session.addSpace(inProfileOf: space)
        let window = open(BrowserWindowState(spaceID: other.id))
        let tab = other.tabManager.newTab(url: URL(string: "about:blank"))
        let detached = open(window.detachToNewWindow(tab))
        session.deleteSpace(other)
        detached.windowDidClose()
        #expect(session.windowTabs.isEmpty)
        #expect(space.tabManager.closedTabs.lastCount == 1)
    }

    @Test func `a restored window whose tabs are gone shows its Space`() {
        let window = open(BrowserWindowState(spaceID: space.id, windowTabsID: UUID()))
        #expect(window.windowTabs == nil)
        #expect(window.space === space)
    }

    @Test func `extensions see the window with only its own tabs`() throws {
        let kept = space.tabManager.newTab()
        let tab = space.tabManager.newTab()
        let window = open(first.detachToNewWindow(tab))
        let windows = ExtensionWindows()
        windows.windowDidAppear(first, window: nil)
        windows.windowDidAppear(window, window: nil)
        windows.update(beforeLoading: true)
        let firstID = try #require(windows.adapter(for: first)?.windowID)
        let windowID = try #require(windows.adapter(for: window)?.windowID)
        #expect(windows.tabs(inWindow: firstID).map(\.tabID) == [kept.id])
        #expect(windows.tabs(inWindow: windowID).map(\.tabID) == [tab.id])
        #expect(windows.activeTab(inWindow: windowID)?.tabID == tab.id)
    }
}
