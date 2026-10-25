import Foundation
@testable import Matcha
import Testing
import WebKit

/// Split view in the tab manager: display, active pane, closing, placement.
@MainActor
@Suite(.webKit)
struct TabManagerSplitTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Today tabs on `about:blank?<name>`, in opening order: the last one is at the top of the sidebar
    /// and selected.
    private func openTabs(_ names: [String]) async throws -> [BrowserTab] {
        let tabs = names.map { manager.newTab(url: blankPage($0)) }
        try await waitUntil { tabs.allSatisfy { $0.url != nil } }
        return tabs
    }

    private func ids(_ tabs: [BrowserTab]) -> [UUID] {
        tabs.map(\.id)
    }

    /// Split [t2, t1, t0] (today: t2, t1, t0), where t0 is the active pane.
    private func threePaneSplit() async throws -> [BrowserTab] {
        let tabs = try await openTabs(["t0", "t1", "t2"])
        #expect(manager.openInSplit(tabs[1]))
        #expect(manager.openInSplit(tabs[0]))
        #expect(ids(manager.displayedTabs) == ids([tabs[2], tabs[1], tabs[0]]))
        expectSplitInvariants(manager.layout)
        return tabs
    }

    // MARK: Opening and display

    @Test func `open in split shows both tabs with the new one active`() async throws {
        let tabs = try await openTabs(["one", "two"])
        #expect(manager.openInSplit(tabs[0]))
        #expect(ids(manager.displayedTabs) == ids([tabs[1], tabs[0]]))
        #expect(manager.selectedTab === tabs[0])
        #expect(manager.displayedSplit?.tabIDs == ids([tabs[1], tabs[0]]))
        let allLoaded = manager.displayedTabs.allSatisfy(\.isLoaded)
        #expect(allLoaded)
        // Already in the displayed split: refused.
        #expect(!manager.openInSplit(tabs[1]))
    }

    @Test func `open in split goes right of the active pane`() async throws {
        let tabs = try await openTabs(["a", "b", "c", "d"])
        manager.openInSplit(tabs[2])
        manager.select(tabs[3])
        manager.openInSplit(tabs[1])
        #expect(ids(manager.displayedTabs) == ids([tabs[3], tabs[1], tabs[2]]))
        #expect(manager.selectedTab === tabs[1])
        #expect(ids(manager.todayTabs) == ids([tabs[3], tabs[1], tabs[2], tabs[0]]))
    }

    @Test func `selecting any member shows the whole group and loads every pane`() throws {
        let stored = (0 ..< 3).map { index in
            StoredTab(id: UUID(), url: blankPage("\(index)"), title: "\(index)", lastActivity: .now - Double(10 - index))
        }
        var layout = SidebarLayout()
        for entry in stored {
            layout.insertToday(entry.id, at: layout.today.count)
        }
        layout.joinSplit(stored[1].id, anchor: stored[0].id, at: 1)
        manager.restore(tabs: stored, layout: layout)
        #expect(manager.tabs.allSatisfy { !$0.isLoaded })

        let first = try #require(manager.tab(withID: stored[0].id))
        manager.select(first)
        #expect(manager.displayedTabIDs == [stored[0].id, stored[1].id])
        let allLoaded = manager.displayedTabs.allSatisfy(\.isLoaded)
        #expect(allLoaded)
        #expect(manager.tab(withID: stored[2].id)?.isLoaded == false)
    }

    @Test func `availability follows the displayed content`() async throws {
        let tabs = try await openTabs(["a", "b", "c", "d", "e", "f"])
        let stranger = TabManager(websiteDataStore: .nonPersistent()).newTab()
        manager.setPlace(tabs[0], to: .favorite)
        #expect(manager.splitAvailability(for: tabs[1].id) == .allowed)
        #expect(manager.splitAvailability(for: tabs[5].id) == .unavailable)
        #expect(manager.splitAvailability(for: tabs[0].id) == .unavailable)
        #expect(manager.splitAvailability(for: stranger.id) == .unavailable)
        for tab in [tabs[4], tabs[3], tabs[2]] {
            manager.openInSplit(tab)
        }
        #expect(manager.displayedTabs.count == 4)
        #expect(manager.splitAvailability(for: tabs[1].id) == .full)
        #expect(!manager.openInSplit(tabs[1]))
    }

    @Test func `a today tab joining a pinned split records its pinned origin`() async throws {
        let tabs = try await openTabs(["today", "pinned"])
        manager.setPlace(tabs[1], to: .pinned)
        #expect(tabs[0].pinnedURL == nil)
        manager.openInSplit(tabs[0])
        #expect(manager.place(of: tabs[0]) == .pinned)
        #expect(tabs[0].pinnedURL == blankPage("today"))
        #expect(manager.layout.pinned == [.tab(tabs[1].id), .tab(tabs[0].id)])
    }

    // MARK: Closing and removal

    @Test func `closing the active today pane selects its neighbor and dissolves at one`() async throws {
        let tabs = try await threePaneSplit()
        manager.select(tabs[1])
        manager.close(tabs[1])
        #expect(manager.selectedTab === tabs[0])
        #expect(ids(manager.displayedTabs) == ids([tabs[2], tabs[0]]))
        manager.close(tabs[0])
        #expect(manager.selectedTab === tabs[2])
        #expect(manager.layout.splits.isEmpty)
        #expect(ids(manager.displayedTabs) == [tabs[2].id])
    }

    @Test func `closing an inactive pane keeps the selection`() async throws {
        let tabs = try await threePaneSplit()
        manager.close(tabs[2])
        #expect(manager.selectedTab === tabs[0])
        #expect(ids(manager.displayedTabs) == ids([tabs[1], tabs[0]]))
    }

    @Test func `closing a pinned split unloads every member and keeps the group`() async throws {
        let tabs = try await openTabs(["other", "a", "b"])
        manager.openInSplit(tabs[1])
        let group = try #require(manager.displayedSplit)
        manager.setSplitPlace(group.id, to: .pinned)
        #expect(tabs[1].pinnedURL == blankPage("a"))
        #expect(manager.hasLoadedTab(inSplit: group.id))

        manager.close(tabs[1])
        #expect(!tabs[1].isLoaded)
        #expect(!tabs[2].isLoaded)
        #expect(!manager.hasLoadedTab(inSplit: group.id))
        #expect(manager.layout.split(withID: group.id)?.tabIDs == ids([tabs[2], tabs[1]]))
        #expect(manager.selectedTab == nil)

        manager.select(tabs[2])
        #expect(ids(manager.displayedTabs) == ids([tabs[2], tabs[1]]))
        #expect(tabs[1].isLoaded)
        #expect(tabs[2].isLoaded)
    }

    @Test func `close split view deletes a today split`() async throws {
        let tabs = try await openTabs(["other", "a", "b"])
        manager.openInSplit(tabs[1])
        let group = try #require(manager.displayedSplit)
        manager.closeSplit(group.id)
        #expect(ids(manager.tabs) == [tabs[0].id])
        #expect(manager.layout.splits.isEmpty)
        #expect(manager.selectedTab === tabs[0])
    }

    @Test func `remove from split shows the neighbor and keeps the tab open`() async throws {
        let tabs = try await threePaneSplit()
        manager.select(tabs[1])
        manager.removeFromSplit(tabs[1])
        expectSplitInvariants(manager.layout)
        #expect(manager.selectedTab === tabs[0])
        #expect(ids(manager.displayedTabs) == ids([tabs[2], tabs[0]]))
        #expect(ids(manager.todayTabs) == ids([tabs[2], tabs[0], tabs[1]]))
        #expect(tabs[1].isLoaded)
    }

    @Test func `separating keeps the active tab selected`() async throws {
        let tabs = try await threePaneSplit()
        let group = try #require(manager.displayedSplit)
        manager.separateSplit(group.id)
        #expect(manager.layout.splits.isEmpty)
        #expect(manager.selectedTab === tabs[0])
        #expect(ids(manager.displayedTabs) == [tabs[0].id])
        #expect(ids(manager.todayTabs) == ids([tabs[2], tabs[1], tabs[0]]))
    }

    @Test func `favoriting the active pane keeps the rest of the split on screen`() async throws {
        let tabs = try await threePaneSplit()
        manager.select(tabs[1])
        manager.setPlace(tabs[1], to: .favorite)
        expectSplitInvariants(manager.layout)
        #expect(manager.selectedTab === tabs[0])
        #expect(ids(manager.displayedTabs) == ids([tabs[2], tabs[0]]))
        #expect(manager.place(of: tabs[1]) == .favorite)
    }

    // MARK: Placement

    @Test func `moving a whole split into pinned pins every member`() async throws {
        let tabs = try await openTabs(["a", "b", "c"])
        manager.openInSplit(tabs[1])
        let group = try #require(manager.displayedSplit)
        manager.moveSplit(group.id, to: .pinned(folder: nil, index: 0))
        expectSplitInvariants(manager.layout)
        #expect(manager.layout.pinned == [.tab(tabs[2].id), .tab(tabs[1].id)])
        #expect(tabs[2].pinnedURL == blankPage("c"))
        #expect(tabs[1].pinnedURL == blankPage("b"))

        manager.moveSplit(group.id, to: .today(index: 1))
        #expect(ids(manager.todayTabs) == ids([tabs[0], tabs[2], tabs[1]]))
        #expect(tabs[2].pinnedURL == nil)
        #expect(tabs[1].pinnedTitle == nil)
    }

    @Test func `close other tabs keeps the tab's split`() async throws {
        let tabs = try await openTabs(["a", "b", "c", "d"])
        manager.openInSplit(tabs[2])
        manager.setPlace(tabs[0], to: .pinned)
        manager.closeOtherTabs(than: tabs[3])
        #expect(ids(manager.todayTabs) == ids([tabs[3], tabs[2]]))
        #expect(manager.place(of: tabs[0]) == .pinned)
        #expect(manager.selectedTab === tabs[3])
        #expect(ids(manager.displayedTabs) == ids([tabs[3], tabs[2]]))
    }

    @Test func `clear today deletes today splits`() async throws {
        let tabs = try await openTabs(["pinned", "a", "b"])
        manager.setPlace(tabs[0], to: .pinned)
        manager.openInSplit(tabs[1])
        manager.clearToday()
        #expect(manager.layout.splits.isEmpty)
        #expect(ids(manager.tabs) == [tabs[0].id])
        #expect(manager.selectedTab == nil)
    }

    @Test func `links from a pane open after the split`() async throws {
        let tabs = try await openTabs(["t0", "t1", "t2"])
        manager.openInSplit(tabs[1])
        let configuration = WebConfigurationFactory().makeConfiguration(websiteDataStore: manager.websiteDataStore)
        let background = manager.insertTab(configuration: configuration, after: tabs[2], select: false)
        #expect(ids(manager.todayTabs) == ids([tabs[2], tabs[1], background, tabs[0]]))
        #expect(manager.split(containing: background) == nil)
        #expect(manager.selectedTab === tabs[1])

        let window = manager.insertTab(configuration: configuration, after: tabs[1], select: true)
        #expect(ids(manager.todayTabs) == ids([tabs[2], tabs[1], window, background, tabs[0]]))
        #expect(ids(manager.displayedTabs) == [window.id])
        expectSplitInvariants(manager.layout)
    }

    @Test func `panes leaving the screen keep their navigation state`() async throws {
        let other = manager.newTab()
        let panes = ["un", "deux"].map { name in
            let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
            tab.load(TestPages.url(name))
            return (tab, name)
        }
        try await waitUntil { panes.allSatisfy { $0.0.title == $0.1 && !$0.0.isLoading } }
        manager.openInSplit(panes[0].0)
        #expect(manager.displayedTabs.count == 2)
        for (tab, _) in panes {
            tab.savedInteractionState = nil
        }
        manager.select(other)
        #expect(panes.allSatisfy { $0.0.savedInteractionState != nil })
    }
}
