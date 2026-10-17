import Foundation
@testable import Matcha
import Testing
import WebKit

/// ⌘1 à ⌘9, ⌃⇥ et ⌃⇧⇥ sur les onglets d'une fenêtre (tâche 4.8).
@MainActor
struct TabManagerShortcutTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Onglets du jour `count`, dans l'ordre de la barre ; le premier est sélectionné.
    private func openTabs(_ count: Int) -> [BrowserTab] {
        let tabs = Array((0 ..< count).map { _ in manager.newTab() }.reversed())
        manager.select(tabs[0])
        return tabs
    }

    @Test func `next and previous follow the selection and wrap around`() {
        let tabs = openTabs(3)
        #expect(manager.adjacentTab(forward: true) === tabs[1])
        #expect(manager.adjacentTab(forward: false) === tabs[2])
        manager.select(tabs[2])
        #expect(manager.adjacentTab(forward: true) === tabs[0])
        #expect(manager.adjacentTab(forward: false) === tabs[1])
    }

    @Test func `a lone tab has no next or previous tab`() {
        _ = openTabs(1)
        #expect(manager.adjacentTab(forward: true) == nil)
        #expect(manager.adjacentTab(forward: false) == nil)
    }

    @Test func `numbers pick favorites then pinned, and nine the last tab`() {
        let tabs = openTabs(4)
        manager.setPlace(tabs[2], to: .favorite)
        manager.setPlace(tabs[3], to: .pinned)
        #expect(manager.numberedTab(1) === tabs[2])
        #expect(manager.numberedTab(2) === tabs[3])
        #expect(manager.numberedTab(3) == nil)
        #expect(manager.lastSidebarTab === tabs[1])
        #expect(manager.title(of: [tabs[2].id]) == tabs[2].displayTitle)
    }

    @Test func `a split row picks its most recently selected pane`() throws {
        let tabs = openTabs(3)
        try #require(manager.openInSplit(tabs[1]))
        let group = try #require(manager.split(containing: tabs[0]))
        #expect(group.tabIDs == [tabs[0].id, tabs[1].id])
        // Le panneau ajouté est sélectionné ; le split revient sur lui.
        #expect(manager.target(of: group.tabIDs) === tabs[1])
        tabs[0].lastActivity = .now.addingTimeInterval(60)
        #expect(manager.target(of: group.tabIDs) === tabs[0])
        #expect(manager.lastSidebarTab === tabs[2])
        #expect(manager.title(of: group.tabIDs) == [tabs[0].displayTitle, tabs[1].displayTitle].formatted(.list(type: .and)))
    }

    @Test func `next steps through each pane of a split`() throws {
        let tabs = openTabs(3)
        try #require(manager.openInSplit(tabs[1]))
        manager.select(tabs[0])
        #expect(manager.adjacentTab(forward: true) === tabs[1])
        manager.select(tabs[1])
        #expect(manager.adjacentTab(forward: true) === tabs[2])
        #expect(manager.adjacentTab(forward: false) === tabs[0])
    }

    @Test func `showing the next tab closes the peek`() throws {
        let tabs = openTabs(2)
        let url = try #require(URL(string: "about:blank"))
        try #require(manager.openPeek(url, from: tabs[0]) != nil)
        let next = try #require(manager.adjacentTab(forward: true))
        manager.select(next)
        #expect(manager.peek == nil)
        #expect(manager.selectedTab === tabs[1])
    }
}
