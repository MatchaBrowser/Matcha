import Foundation
@testable import Matcha
import Testing
import WebKit

/// Names of pinned tabs and favorites (`TabManager+Names`): shown in place of the page's title, never for a today tab.
@MainActor
@Suite(.webKit)
struct TabNameTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    private func pinnedTab(named name: String? = nil) -> BrowserTab {
        let tab = manager.newTab()
        manager.setPlace(tab, to: .pinned)
        if let name {
            manager.renameTab(tab, to: name)
        }
        return tab
    }

    @Test func `a pinned tab or a favorite takes a name, a today tab doesn't`() {
        let tab = manager.newTab()
        #expect(!manager.canRename(tab))
        manager.renameTab(tab, to: "Courrier")
        #expect(tab.customTitle == nil)

        manager.setPlace(tab, to: .pinned)
        manager.renameTab(tab, to: "  Courrier \n")
        #expect(tab.customTitle == "Courrier")
        #expect(tab.displayTitle == "Courrier")
        #expect(tab.pageTitle == String(localized: "New Tab"))
        // A favorite keeps it; back among the today tabs, the tab forgets it.
        manager.setPlace(tab, to: .favorite)
        #expect(tab.displayTitle == "Courrier")
        manager.setPlace(tab, to: .today)
        #expect(tab.customTitle == nil)
    }

    @Test func `an empty name gives the page's title back, the title shown changes nothing`() {
        let tab = pinnedTab()
        manager.renameTab(tab, to: tab.displayTitle)
        #expect(tab.customTitle == nil)
        manager.renameTab(tab, to: "Courrier")
        manager.renameTab(tab, to: "Courrier")
        #expect(tab.customTitle == "Courrier")
        manager.renameTab(tab, to: "   ")
        #expect(tab.customTitle == nil)
        #expect(tab.displayTitle == tab.pageTitle)
    }

    @Test func `renaming or leaving ends the editing of the row`() {
        let first = pinnedTab()
        let second = pinnedTab()
        manager.renamingTabID = first.id
        manager.endRenaming(second)
        #expect(manager.renamingTabID == first.id)
        manager.renameTab(first, to: "Courrier")
        #expect(manager.renamingTabID == nil)
        manager.renamingTabID = second.id
        manager.endRenaming(second)
        #expect(manager.renamingTabID == nil && second.customTitle == nil)
    }

    @Test func `a closed pinned tab keeps its name`() {
        let tab = pinnedTab(named: "Courrier")
        manager.close(tab)
        #expect(manager.place(of: tab) == .pinned)
        #expect(tab.displayTitle == "Courrier")
    }

    @Test func `a tab moved to another Space keeps its name, unless it becomes a today tab there`() throws {
        let other = TabManager(websiteDataStore: manager.websiteDataStore)
        let tab = pinnedTab(named: "Courrier")
        try other.attach(#require(manager.detach(tab)), at: .pinned(folder: nil, index: 0))
        #expect(tab.customTitle == "Courrier")
        try manager.attach(#require(other.detach(tab)))
        #expect(manager.place(of: tab) == .today && tab.customTitle == nil)
    }

    /// Review IU5: the Tabs menu shows the name rather than the title the tab had when pinned.
    @Test func `the Tabs menu shows the name`() {
        let tab = pinnedTab()
        tab.pinnedTitle = "Gmail"
        manager.renameTab(tab, to: "Courrier")
        #expect(manager.title(of: [tab.id]) == "Courrier")
    }
}
