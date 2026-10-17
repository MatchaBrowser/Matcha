import Foundation
@testable import Matcha
import Testing
import WebKit

/// Séquence du test d'interface « glisser vers les favoris et les épinglés », sans la souris.
@MainActor
struct TabManagerDragRegressionTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    @Test func `pinned tab survives clearing today after favorites and pinned drags`() {
        let tabs = (0 ..< 3).map { _ in manager.newTab() }
        // Barre : tabs[2], tabs[1], tabs[0] (le dernier ouvert en tête).
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
