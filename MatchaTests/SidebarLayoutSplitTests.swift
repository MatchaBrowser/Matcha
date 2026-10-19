import Foundation
@testable import Matcha
import Testing

/// Split rules in the sidebar layout (continued in `SidebarLayoutSplitTests+Groups.swift`).
struct SidebarLayoutSplitTests {
    let ids = (0 ..< 8).map { _ in UUID() }

    /// Today tabs `ids[0]`… `ids[count - 1]`, in this order.
    func todayLayout(_ count: Int) -> SidebarLayout {
        var layout = SidebarLayout()
        for id in ids.prefix(count) {
            layout.insertToday(id, at: layout.today.count)
        }
        return layout
    }

    /// Split of `members` (indices in `ids`), each added to the right of the previous one.
    @discardableResult
    func group(_ members: [Int], in layout: inout SidebarLayout) -> UUID? {
        var groupID: UUID?
        for (offset, member) in members.enumerated().dropFirst() {
            groupID = layout.joinSplit(ids[member], anchor: ids[members[0]], at: offset)
        }
        return groupID
    }

    func today(_ layout: SidebarLayout) -> [Int] {
        layout.today.compactMap { ids.firstIndex(of: $0) }
    }

    func members(_ group: SplitGroup?) -> [Int] {
        group?.tabIDs.compactMap { ids.firstIndex(of: $0) } ?? []
    }

    // MARK: Creation

    @Test func `joining builds a group in pane order on either side`() throws {
        var layout = todayLayout(5)
        let joined = layout.joinSplit(ids[3], anchor: ids[1], at: 1)
        let groupID = try #require(joined)
        expectSplitInvariants(layout)
        #expect(today(layout) == [0, 1, 3, 2, 4])
        #expect(members(layout.split(withID: groupID)) == [1, 3])
        #expect(layout.split(withID: groupID)?.fractions == [0.5, 0.5])

        let rejoined = layout.joinSplit(ids[4], anchor: ids[1], at: 0)
        #expect(rejoined == groupID)
        expectSplitInvariants(layout)
        #expect(today(layout) == [0, 4, 1, 3, 2])
        #expect(members(layout.split(containing: ids[3])) == [4, 1, 3])
        #expect(layout.splits.count == 1)
    }

    @Test func `the joined tab moves next to the anchor`() {
        var layout = todayLayout(4)
        layout.joinSplit(ids[0], anchor: ids[2], at: 1)
        expectSplitInvariants(layout)
        #expect(today(layout) == [1, 2, 0, 3])
        #expect(members(layout.split(containing: ids[2])) == [2, 0])
    }

    @Test func `a today tab joining a pinned anchor becomes pinned in its folder`() {
        var layout = todayLayout(3)
        let folder = layout.addFolder(named: "Travail")
        layout.move(ids[0], to: .pinned(folder: folder, index: 0))
        layout.joinSplit(ids[2], anchor: ids[0], at: 1)
        expectSplitInvariants(layout)
        #expect(layout.place(of: ids[2]) == .pinned)
        #expect(layout.pinned.folder(folder)?.items == [.tab(ids[0]), .tab(ids[2])])
        #expect(today(layout) == [1])
    }

    @Test func `a pinned tab brings a today group to its own place`() {
        var layout = todayLayout(5)
        layout.setPlace(ids[0], to: .pinned)
        layout.setPlace(ids[1], to: .pinned)
        group([2, 3], in: &layout)
        layout.joinSplit(ids[1], anchor: ids[2], at: 2)
        expectSplitInvariants(layout)
        // Nothing is unpinned: the today split joins the pinned tab in its section.
        #expect(layout.pinned == [.tab(ids[0]), .tab(ids[2]), .tab(ids[3]), .tab(ids[1])])
        #expect(today(layout) == [4])
        #expect(members(layout.split(containing: ids[1])) == [2, 3, 1])
    }

    @Test func `favorites can neither anchor nor join`() {
        var layout = todayLayout(3)
        layout.setPlace(ids[0], to: .favorite)
        let favoriteAnchor = layout.joinSplit(ids[1], anchor: ids[0], at: 1)
        let favoriteTab = layout.joinSplit(ids[0], anchor: ids[1], at: 1)
        #expect(favoriteAnchor == nil)
        #expect(favoriteTab == nil)
        #expect(layout.splits.isEmpty)
        // A favorite dragged into a split leaves it at once.
        layout.setSplits([SplitGroup(tabIDs: [ids[0], ids[1], ids[2]])])
        expectSplitInvariants(layout)
        #expect(members(layout.splits.first) == [1, 2])
    }

    @Test func `a full group reports full and refuses a fifth tab`() {
        var layout = todayLayout(5)
        group([0, 1, 2, 3], in: &layout)
        #expect(layout.splitAvailability(of: ids[4], anchor: ids[2]) == .full)
        let before = layout
        let fifth = layout.joinSplit(ids[4], anchor: ids[2], at: 4)
        #expect(fifth == nil)
        #expect(layout == before)
    }

    @Test func `joining from another group leaves it and dissolves a group of two`() {
        var layout = todayLayout(4)
        group([0, 1], in: &layout)
        group([2, 3], in: &layout)
        #expect(layout.splits.count == 2)
        layout.joinSplit(ids[3], anchor: ids[0], at: 2)
        expectSplitInvariants(layout)
        #expect(layout.splits.count == 1)
        #expect(members(layout.split(containing: ids[0])) == [0, 1, 3])
        #expect(layout.split(containing: ids[2]) == nil)
        #expect(today(layout) == [0, 1, 3, 2])
    }

    /// Tab and anchor, by their index in `ids` (`ids[7]` is never placed), and expected availability.
    struct AvailabilityCase: Sendable, CustomTestStringConvertible {
        let name: String
        let tab: Int
        let anchor: Int?
        let expected: SplitAvailability

        var testDescription: String {
            name
        }
    }

    static let availabilityCases = [
        AvailabilityCase(name: "sans ancre", tab: 4, anchor: nil, expected: .unavailable),
        AvailabilityCase(name: "lui-même", tab: 4, anchor: 4, expected: .unavailable),
        AvailabilityCase(name: "favori", tab: 6, anchor: 4, expected: .unavailable),
        AvailabilityCase(name: "ancre favorite", tab: 4, anchor: 6, expected: .unavailable),
        AvailabilityCase(name: "onglet inconnu", tab: 7, anchor: 4, expected: .unavailable),
        AvailabilityCase(name: "déjà membre", tab: 1, anchor: 0, expected: .unavailable),
        AvailabilityCase(name: "split plein", tab: 4, anchor: 0, expected: .full),
        AvailabilityCase(name: "possible", tab: 4, anchor: 5, expected: .allowed),
        AvailabilityCase(name: "membre d'un autre split", tab: 0, anchor: 4, expected: .allowed),
    ]

    @Test(arguments: availabilityCases)
    func `availability matrix`(situation: AvailabilityCase) {
        // Today: 0 to 5, including the full split [0, 1, 2, 3]; favorite: 6.
        var layout = todayLayout(6)
        layout.setPlace(ids[6], to: .favorite)
        group([0, 1, 2, 3], in: &layout)
        let anchor = situation.anchor.map { ids[$0] }
        #expect(layout.splitAvailability(of: ids[situation.tab], anchor: anchor) == situation.expected)
    }

    // MARK: Removal and rules

    @Test func `remove from split puts the tab right after the group`() {
        var layout = todayLayout(5)
        group([0, 1, 2], in: &layout)
        layout.removeFromSplit(ids[0])
        expectSplitInvariants(layout)
        #expect(today(layout) == [1, 2, 0, 3, 4])
        #expect(members(layout.split(containing: ids[1])) == [1, 2])
        layout.removeFromSplit(ids[1])
        expectSplitInvariants(layout)
        #expect(today(layout) == [2, 1, 0, 3, 4])
        #expect(layout.splits.isEmpty)
    }

    @Test func `removing a member shrinks the group and dissolves it at one`() {
        var layout = todayLayout(4)
        group([0, 1, 2], in: &layout)
        layout.remove(ids[1])
        expectSplitInvariants(layout)
        #expect(members(layout.splits.first) == [0, 2])
        layout.remove(ids[0])
        expectSplitInvariants(layout)
        #expect(layout.splits.isEmpty)
        #expect(today(layout) == [2, 3])
    }

    @Test func `moving, pinning or favoriting a member takes it out`() {
        var layout = todayLayout(6)
        group([0, 1, 2, 3, 4], in: &layout)
        #expect(members(layout.splits.first) == [0, 1, 2, 3])
        layout.move(ids[1], to: .today(index: 6))
        expectSplitInvariants(layout)
        #expect(members(layout.splits.first) == [0, 2, 3])
        #expect(today(layout) == [0, 2, 3, 4, 5, 1])
        layout.setPlace(ids[2], to: .pinned)
        expectSplitInvariants(layout)
        #expect(members(layout.splits.first) == [0, 3])
        layout.insertToday(ids[3], at: 0)
        expectSplitInvariants(layout)
        #expect(layout.splits.isEmpty)
        group([0, 4], in: &layout)
        layout.setPlace(ids[4], to: .favorite)
        expectSplitInvariants(layout)
        #expect(layout.splits.isEmpty)
    }

    @Test func `a tab inserted inside a group goes after it`() {
        var layout = todayLayout(4)
        group([1, 2], in: &layout)
        layout.insertToday(ids[4], at: 2)
        expectSplitInvariants(layout)
        #expect(today(layout) == [0, 1, 2, 4, 3])

        layout.setSplitPlace(layout.splits[0].id, to: .pinned)
        let folder = layout.addFolder(named: "Travail", at: 1)
        expectSplitInvariants(layout)
        #expect(layout.pinned.map(\.id) == [ids[1], ids[2], folder])
    }
}
