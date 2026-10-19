import Foundation
@testable import Matcha
import Testing
import WebKit

/// Sequence of the UI test “dragging tabs to favorites and pinned”, without the mouse.
@MainActor
struct TabManagerDragRegressionTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    @Test func `pinned tab survives clearing today after favorites and pinned drags`() {
        let tabs = (0 ..< 3).map { _ in manager.newTab() }
        // Sidebar: tabs[2], tabs[1], tabs[0] (the last one opened on top).
        manager.move(tabs[2], to: .favorites(index: 0))
        #expect(manager.todayTabs.map(\.id) == [tabs[1].id, tabs[0].id])
        manager.move(tabs[0], to: .pinned(folder: nil, index: 0))
        #expect(manager.place(of: tabs[0]) == .pinned)
        manager.clearToday()
        #expect(manager.todayTabs.isEmpty)
        #expect(manager.layout.pinned.flatMap(\.tabIDs) == [tabs[0].id])
        #expect(manager.layout.favorites == [tabs[2].id])
        #expect(manager.tabs.count == 2)
    }
}
