import Foundation
@testable import Matcha
import SwiftUI
import Testing
import WebKit

/// Moving a tab or a folder one step without dragging (audit H3: VoiceOver actions, ⌥⌘↑ and ⌥⌘↓).
struct SidebarStepTests {
    private let ids = (0 ..< 6).map { _ in UUID() }

    private func moved(_ layout: SidebarLayout, _ index: Int, by offset: Int) -> SidebarLayout? {
        var layout = layout
        guard let destination = layout.stepDestination(of: ids[index], by: offset) else {
            return nil
        }
        layout.move(ids[index], to: destination)
        return layout
    }

    private func indices(_ tabIDs: [UUID]) -> [Int] {
        tabIDs.compactMap { ids.firstIndex(of: $0) }
    }

    @Test func `a today tab moves one step and stops at the edges`() throws {
        var layout = SidebarLayout()
        [0, 1, 2].forEach { layout.insertToday(ids[$0], at: layout.today.count) }
        #expect(try indices(#require(moved(layout, 1, by: -1)).today) == [1, 0, 2])
        #expect(try indices(#require(moved(layout, 1, by: 1)).today) == [0, 2, 1])
        #expect(try indices(#require(moved(layout, 0, by: 1)).today) == [1, 0, 2])
        #expect(moved(layout, 0, by: -1) == nil)
        #expect(moved(layout, 2, by: 1) == nil)
    }

    @Test func `favorites and pinned tabs stay in their list`() throws {
        var layout = SidebarLayout()
        [0, 1].forEach { layout.setPlace(ids[$0], to: .favorite) }
        [2, 3].forEach { layout.setPlace(ids[$0], to: .pinned) }
        #expect(try indices(#require(moved(layout, 1, by: -1)).favorites) == [1, 0])
        #expect(moved(layout, 1, by: 1) == nil)
        #expect(moved(layout, 2, by: -1) == nil)
        #expect(try indices(#require(moved(layout, 2, by: 1)).pinned.flatMap(\.tabIDs)) == [3, 2])
    }

    @Test func `inside a folder and around a folder`() throws {
        var layout = SidebarLayout()
        layout.setPlace(ids[0], to: .pinned)
        let folder = layout.addFolder(named: "Dossier")
        for index in [1, 2] {
            layout.setPlace(ids[index], to: .pinned)
            layout.move(ids[index], to: .pinned(folder: folder, index: 9))
        }
        #expect(layout.pinned.folder(folder)?.items.map(\.id) == [ids[1], ids[2]])

        let inside = try #require(moved(layout, 2, by: -1))
        #expect(inside.pinned.folder(folder)?.items.map(\.id) == [ids[2], ids[1]])
        #expect(moved(layout, 1, by: -1) == nil)

        // The folder itself goes above the tab before it.
        let destination = try #require(layout.stepDestination(of: folder, by: -1))
        layout.moveFolder(folder, to: destination)
        #expect(layout.pinned.map(\.id) == [folder, ids[0]])
    }

    @MainActor
    @Test func `the manager moves a tab and says when it can't`() {
        let manager = TabManager(websiteDataStore: .nonPersistent())
        let first = manager.newTab()
        let second = manager.newTab()
        #expect(manager.todayTabs.map(\.id) == [second.id, first.id])
        #expect(!manager.canMoveStep(second, by: -1))
        #expect(manager.moveStep(second, by: 1))
        #expect(manager.todayTabs.map(\.id) == [first.id, second.id])
        #expect(!manager.moveStep(second, by: 1))
    }

    @MainActor
    @Test func `reduced motion has no animation`() {
        #expect(Motion.animation(.default, reduced: true) == nil)
        #expect(Motion.animation(.default, reduced: false) == .default)
    }
}
