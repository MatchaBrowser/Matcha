import Foundation
@testable import Matcha
import Testing
import WebKit

/// History > Reopen Closed Tab (⇧⌘T, audit H2): what the user closed comes back at its place, a whole “Clear” at once.
@MainActor
@Suite(.webKit)
struct ClosedTabsTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// A today tab at the top, showing the local page `name`.
    private func pageTab(_ name: String) async throws -> BrowserTab {
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url(name))
        try await waitUntil { tab.title == name && !tab.isLoading }
        return tab
    }

    @Test func `a closed tab comes back at its place with its page`() async throws {
        let first = try await pageTab("un")
        let second = try await pageTab("deux")
        let third = try await pageTab("trois")
        #expect(manager.todayTabs.map(\.title) == ["trois", "deux", "un"])

        manager.close(second)
        #expect(manager.todayTabs.map(\.title) == ["trois", "un"])
        #expect(manager.closedTabs.lastCount == 1)

        // A new tab with the same page and history (the test pages only load in their own configuration: the order
        // is checked by identifier).
        let reopened = try #require(manager.reopenClosedTabs().first)
        #expect(manager.todayTabs.map(\.id) == [third.id, reopened.id, first.id])
        #expect(manager.selectedTab === reopened)
        #expect(reopened.url == TestPages.url("deux"))
        #expect(reopened !== second)
        #expect(manager.closedTabs.isEmpty)
        #expect(manager.reopenClosedTabs().isEmpty)
    }

    @Test func `clear and close other tabs come back all at once`() async throws {
        let kept = try await pageTab("gardé")
        _ = try await pageTab("a")
        _ = try await pageTab("b")
        manager.closeOtherTabs(than: kept)
        #expect(manager.todayTabs.map(\.title) == ["gardé"])
        #expect(manager.closedTabs.lastCount == 2)
        manager.clearToday()
        #expect(manager.todayTabs.isEmpty)

        let cleared = manager.reopenClosedTabs()
        #expect(cleared.map(\.url) == [TestPages.url("gardé")])
        let others = manager.reopenClosedTabs()
        #expect(others.map(\.url) == [TestPages.url("b"), TestPages.url("a")])
        #expect(manager.todayTabs.map(\.id) == (others + cleared).map(\.id))
    }

    @Test func `a deleted pinned tab comes back pinned`() async throws {
        let tab = try await pageTab("épinglé")
        manager.setPlace(tab, to: .pinned)
        manager.delete(tab, reopenable: true)
        #expect(manager.tabs.isEmpty)

        let reopened = try #require(manager.reopenClosedTabs().first)
        #expect(manager.place(of: reopened) == .pinned)
        #expect(reopened.pinnedURL == TestPages.url("épinglé"))
    }

    @Test func `an empty tab or a tab moving elsewhere is not kept`() async throws {
        manager.close(manager.newTab())
        let moving = try await pageTab("ailleurs")
        manager.delete(moving)
        #expect(manager.closedTabs.isEmpty)
    }

    @Test func `only the last groups are kept`() {
        var groups = ClosedTabGroups()
        let stored = StoredTab(
            id: UUID(),
            url: nil,
            title: nil,
            pinnedURL: nil,
            pinnedTitle: nil,
            lastActivity: .now,
            interactionState: nil,
        )
        for _ in 0 ..< ClosedTabGroups.maximumCount + 5 {
            groups.append([ClosedTab(stored: stored, place: .today, todayIndex: 0)])
        }
        groups.append([])
        #expect(groups.groups.count == ClosedTabGroups.maximumCount)
    }
}
