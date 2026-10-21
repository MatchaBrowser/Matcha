import Foundation
@testable import Matcha
import Testing
import WebKit

/// Which tab is selected, and where the selection goes when the selected tab closes.
@MainActor
struct TabManagerSelectionTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Opens `count` empty tabs; the last one opened is at the top of the sidebar.
    private func openTabs(_ count: Int) -> [BrowserTab] {
        (0 ..< count).map { _ in manager.newTab() }
    }

    private func ids(_ tabs: [BrowserTab]) -> [UUID] {
        tabs.map(\.id)
    }

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

    @Test func `closing a selected pinned tab or favorite shows the empty page`() {
        let tabs = openTabs(4) // today: 3, 2, 1, 0
        manager.setPlace(tabs[0], to: .pinned)
        manager.setPlace(tabs[1], to: .pinned)
        manager.setPlace(tabs[2], to: .favorite)
        // Neither the other pinned tab nor the today tab: they would load a page by themselves.
        manager.select(tabs[0])
        manager.close(tabs[0])
        #expect(manager.selectedTab == nil)
        manager.select(tabs[2])
        manager.close(tabs[2])
        #expect(manager.selectedTab == nil)
        #expect(manager.tabs.count == 4)
    }

    @Test func `closing the last today tab shows the empty page, not a pinned tab or a favorite`() {
        let tabs = openTabs(4) // today: 3, 2, 1, 0
        manager.setPlace(tabs[0], to: .pinned)
        manager.setPlace(tabs[1], to: .favorite)
        // Today: 3, 2. The neighbor is a today tab, then nothing.
        manager.select(tabs[2])
        manager.close(tabs[2])
        #expect(manager.selectedTab === tabs[3])
        manager.close(tabs[3])
        #expect(manager.selectedTab == nil)
        #expect(ids(manager.tabs) == [tabs[1].id, tabs[0].id])
    }
}
