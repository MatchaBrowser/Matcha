import AppKit
import Foundation
@testable import Matcha
import Testing
import WebKit

@MainActor
struct TabManagerTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Opens `count` empty tabs; the last one opened is at the top of the sidebar.
    private func openTabs(_ count: Int) -> [BrowserTab] {
        (0 ..< count).map { _ in manager.newTab() }
    }

    private func ids(_ tabs: [BrowserTab]) -> [UUID] {
        tabs.map(\.id)
    }

    // MARK: Opening

    @Test func `starts without tabs`() {
        #expect(manager.tabs.isEmpty)
        #expect(manager.selectedTab == nil)
    }

    @Test func `new tab goes on top of today's tabs and is selected`() {
        let tabs = openTabs(3)
        #expect(ids(manager.todayTabs) == ids(tabs.reversed()))
        #expect(manager.place(of: tabs[0]) == .today)
        #expect(manager.selectedTab === tabs[2])
    }

    @Test func `new tab uses the manager data store`() {
        let tab = manager.newTab()
        #expect(tab.loadedWebView.configuration.websiteDataStore === manager.websiteDataStore)
    }

    @Test func `new tab loads the given url`() async throws {
        let url = try #require(URL(string: "about:blank"))
        let tab = manager.newTab(url: url)
        try await waitUntil { tab.url == url && !tab.isLoading }
    }

    @Test func `background tab keeps the selection`() {
        let tabs = openTabs(2)
        let background = manager.newTab(select: false)
        #expect(manager.todayTabs.first === background)
        #expect(manager.selectedTab === tabs[1])
    }

    @Test func `first tab is selected even in background`() {
        let tab = manager.newTab(select: false)
        #expect(manager.selectedTab === tab)
    }

    @Test func `inserted tab goes after its opener and its previous children`() {
        let tabs = openTabs(3) // today: 2, 1, 0
        let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: manager.websiteDataStore)
        let child1 = manager.insertTab(configuration: configuration, after: tabs[1], select: false)
        let child2 = manager.insertTab(configuration: configuration, after: tabs[1], select: false)
        #expect(ids(manager.todayTabs) == [tabs[2].id, tabs[1].id, child1.id, child2.id, tabs[0].id])
        #expect(child1.openerID == tabs[1].id)
        #expect(manager.selectedTab === tabs[2])
    }

    @Test func `tab opened from a pinned tab goes on top of today's tabs`() {
        let tabs = openTabs(2)
        manager.setPlace(tabs[0], to: .pinned)
        let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: manager.websiteDataStore)
        let child = manager.insertTab(configuration: configuration, after: tabs[0], select: true)
        #expect(manager.todayTabs.first === child)
        #expect(manager.selectedTab === child)
    }

    @Test func `tab for web view finds its owner`() {
        let tabs = openTabs(2)
        #expect(manager.tab(for: tabs[1].loadedWebView) === tabs[1])
        #expect(manager.tab(for: WKWebView()) == nil)
        #expect(manager.tab(withID: tabs[0].id) === tabs[0])
    }

    // MARK: Selection and closing

    @Test func `select changes the selected tab`() {
        let tabs = openTabs(3)
        manager.select(tabs[0])
        #expect(manager.selectedTab === tabs[0])
    }

    @Test func `select ignores a tab from elsewhere`() {
        let tabs = openTabs(2)
        let stranger = TabManager(websiteDataStore: .nonPersistent()).newTab()
        manager.select(stranger)
        #expect(manager.selectedTab === tabs[1])
    }

    @Test func `closing the selected tab selects the next one`() {
        let tabs = openTabs(3) // order: 2, 1, 0
        manager.select(tabs[1])
        manager.close(tabs[1])
        #expect(ids(manager.tabs) == [tabs[2].id, tabs[0].id])
        #expect(manager.selectedTab === tabs[0])
    }

    @Test func `closing the selected last tab selects the previous one`() {
        let tabs = openTabs(3) // order: 2, 1, 0
        manager.select(tabs[0])
        manager.close(tabs[0])
        #expect(manager.selectedTab === tabs[1])
    }

    @Test func `closing the selected first tab selects the new first one`() {
        let tabs = openTabs(3) // order: 2, 1, 0
        manager.close(tabs[2])
        #expect(manager.selectedTab === tabs[1])
    }

    @Test func `closing another tab keeps the selection`() {
        let tabs = openTabs(3)
        manager.select(tabs[2])
        manager.close(tabs[0])
        #expect(manager.selectedTab === tabs[2])
    }

    @Test func `closing the only tab clears the selection`() {
        let tab = manager.newTab()
        manager.close(tab)
        #expect(manager.tabs.isEmpty)
        #expect(manager.selectedTab == nil)
    }

    @Test func `closing an unknown tab does nothing`() {
        let tabs = openTabs(2)
        let stranger = TabManager(websiteDataStore: .nonPersistent()).newTab()
        manager.close(stranger)
        #expect(manager.tabs.count == 2)
        #expect(manager.selectedTab === tabs[1])
    }

    @Test func `closing a selected pinned tab moves to its neighbor across sections`() {
        let tabs = openTabs(2) // today: 1, 0
        manager.setPlace(tabs[0], to: .pinned)
        manager.select(tabs[0])
        manager.close(tabs[0])
        #expect(manager.selectedTab === tabs[1])
    }

    // MARK: Places

    @Test func `tabs are ordered favorites then pinned then today`() {
        let tabs = openTabs(4) // today: 3, 2, 1, 0
        manager.setPlace(tabs[0], to: .pinned)
        manager.setPlace(tabs[1], to: .favorite)
        #expect(ids(manager.tabs) == [tabs[1].id, tabs[0].id, tabs[3].id, tabs[2].id])
        #expect(ids(manager.favoriteTabs) == [tabs[1].id])
        #expect(manager.layout.pinned == [.tab(tabs[0].id)])
        #expect(manager.place(of: tabs[1]) == .favorite)
    }

    @Test func `clear today closes only today's tabs`() {
        let tabs = openTabs(3)
        manager.setPlace(tabs[0], to: .pinned)
        manager.clearToday()
        #expect(ids(manager.tabs) == [tabs[0].id])
        #expect(manager.selectedTab === tabs[0])
    }

    @Test func `clear today keeps a pinned selection`() {
        let tabs = openTabs(3)
        manager.setPlace(tabs[0], to: .pinned)
        manager.setPlace(tabs[1], to: .favorite)
        manager.select(tabs[0])
        manager.clearToday()
        #expect(manager.selectedTab === tabs[0])
        #expect(manager.todayTabs.isEmpty)
    }

    @Test func `clear today without other tabs clears the selection`() {
        _ = openTabs(2)
        manager.clearToday()
        #expect(manager.tabs.isEmpty)
        #expect(manager.selectedTab == nil)
    }

    // MARK: Folders

    @Test func `new folder opens its renaming and expands its parent`() {
        let parent = manager.newFolder()
        #expect(manager.renamingFolderID == parent)
        manager.toggleFolder(parent)
        #expect(manager.layout.pinned.folder(parent)?.isCollapsed == true)

        let child = manager.newFolder(in: parent)
        #expect(manager.renamingFolderID == child)
        #expect(manager.layout.pinned.folder(parent)?.isCollapsed == false)
        #expect(manager.layout.pinned.location(of: child)?.parent == parent)
    }

    @Test func `renaming trims and keeps the old name when empty`() {
        let folder = manager.newFolder()
        manager.renameFolder(folder, to: "  Travail  ")
        #expect(manager.layout.pinned.folder(folder)?.name == "Travail")
        #expect(manager.renamingFolderID == nil)
        manager.renameFolder(folder, to: "   ")
        #expect(manager.layout.pinned.folder(folder)?.name == "Travail")
    }

    @Test func `deleting a folder keeps its tabs pinned`() {
        let tabs = openTabs(2)
        let folder = manager.newFolder()
        manager.move(tabs[0], to: .pinned(folder: folder, index: 0))
        manager.deleteFolder(folder)
        #expect(manager.layout.pinned == [.tab(tabs[0].id)])
        #expect(manager.tabs.count == 2)
    }

    // MARK: Context menu

    @Test func `duplicate opens a copy right after the tab with its history`() async throws {
        let other = manager.newTab()
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url("un"))
        try await waitUntil { tab.title == "un" && !tab.isLoading }
        tab.load(TestPages.url("deux"))
        try await waitUntil { tab.title == "deux" && tab.canGoBack }

        let copy = manager.duplicate(tab)
        #expect(ids(manager.todayTabs) == [tab.id, copy.id, other.id])
        #expect(manager.selectedTab === copy)
        try await waitUntil { copy.title == "deux" && copy.canGoBack }
        #expect(copy.url == tab.url)
    }

    @Test func `duplicate of a blank tab is blank`() {
        let tab = manager.newTab()
        let copy = manager.duplicate(tab)
        #expect(copy.url == nil)
        #expect(manager.tabs.count == 2)
    }

    @Test func `close other tabs keeps pinned and favorites`() {
        let tabs = openTabs(5)
        manager.setPlace(tabs[0], to: .pinned)
        manager.setPlace(tabs[1], to: .favorite)
        manager.closeOtherTabs(than: tabs[3])
        #expect(ids(manager.tabs) == [tabs[1].id, tabs[0].id, tabs[3].id])
        #expect(manager.selectedTab === tabs[3])
    }

    @Test func `copy link writes url and text`() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("matcha-tests-\(UUID().uuidString)"))
        let url = try #require(URL(string: "https://example.com/page?x=1"))
        TabLinkCopier.copy(url, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "https://example.com/page?x=1")
        #expect(pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] == [url])
        pasteboard.releaseGlobally()
    }

    // MARK: Arc-style pinned tabs

    /// Tab loaded with the local page `name`, placed at `place`, and another today tab.
    private func loadedTab(_ name: String, place: TabPlace) async throws -> (tab: BrowserTab, other: BrowserTab) {
        let other = manager.newTab()
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url(name))
        try await waitUntil { tab.title == name && !tab.isLoading }
        manager.setPlace(tab, to: place)
        return (tab, other)
    }

    @Test(arguments: [TabPlace.pinned, .favorite])
    func `closing a pinned or favorite tab unloads it back to its origin`(place: TabPlace) async throws {
        let (tab, other) = try await loadedTab("origine", place: place)
        #expect(tab.pinnedURL == TestPages.url("origine"))
        tab.load(TestPages.url("ailleurs"))
        try await waitUntil { tab.title == "ailleurs" && !tab.isLoading }

        manager.close(tab)
        #expect(manager.place(of: tab) == place)
        #expect(!tab.isLoaded)
        #expect(tab.url == TestPages.url("origine"))
        #expect(tab.title == "origine")
        #expect(manager.selectedTab === other)

        manager.select(tab)
        #expect(tab.isLoaded)
        try await waitUntil { tab.title == "origine" && !tab.isLoading }
        #expect(!tab.canGoBack)
    }

    @Test func `delete removes a pinned tab`() async throws {
        let (tab, other) = try await loadedTab("origine", place: .pinned)
        manager.delete(tab)
        #expect(manager.tab(withID: tab.id) == nil)
        #expect(manager.layout.pinned.isEmpty)
        #expect(manager.selectedTab === other)
    }

    @Test func `pinned origin is kept across places and forgotten in today`() async throws {
        let (tab, _) = try await loadedTab("origine", place: .pinned)
        tab.load(TestPages.url("ailleurs"))
        try await waitUntil { tab.title == "ailleurs" && !tab.isLoading }
        manager.setPlace(tab, to: .favorite)
        #expect(tab.pinnedURL == TestPages.url("origine"))
        manager.move(tab, to: .today(index: 0))
        #expect(tab.pinnedURL == nil)
        #expect(tab.pinnedTitle == nil)
    }
}
