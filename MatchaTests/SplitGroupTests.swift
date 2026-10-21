import Foundation
@testable import Matcha
import Testing

struct SplitGroupTests {
    private let ids = (0 ..< 5).map { _ in UUID() }

    @Test func `new group normalizes its fractions`() {
        let group = SplitGroup(tabIDs: [ids[0], ids[1]], fractions: [1, 3])
        #expect(group.fractions == [0.25, 0.75])
        #expect(SplitGroup(tabIDs: [ids[0], ids[1], ids[2]]).fractions == SplitGroup.equalFractions(count: 3))
        #expect(SplitGroup(tabIDs: [ids[0], ids[1], ids[0]]).tabIDs == [ids[0], ids[1]])
    }

    @Test(arguments: [[Double.nan, 0.5], [-0.2, 1.2], [0, 1], [0, 0], [0.5], [0.2, 0.3, 0.5], [.infinity, 1]])
    func `invalid fractions become equal shares`(fractions: [Double]) {
        #expect(SplitGroup.normalizedFractions(fractions, count: 2) == [0.5, 0.5])
    }

    @Test func `valid fractions are kept exactly`() {
        let fractions = [0.1, 0.2, 0.3, 0.4]
        #expect(SplitGroup.normalizedFractions(fractions, count: 4) == fractions)
        // Typed apart: inside `#expect`, Xcode 26's compiler gives up on this literal (CI).
        let thirds: [Double] = [1 / 3.0, 2 / 3.0]
        #expect(SplitGroup.normalizedFractions(thirds, count: 2) == thirds)
        #expect(SplitGroup.normalizedFractions([], count: 0).isEmpty)
        #expect(SplitGroup.equalFractions(count: 0).isEmpty)
    }

    @Test func `inserting a pane gives it an equal share and keeps the others' proportions`() {
        var group = SplitGroup(tabIDs: [ids[0], ids[1]], fractions: [0.25, 0.75])
        group.insert(ids[2], at: 1)
        #expect(group.tabIDs == [ids[0], ids[2], ids[1]])
        #expect(abs(group.fractions[0] - 0.25 * 2 / 3) < 1e-12)
        #expect(abs(group.fractions[1] - 1 / 3.0) < 1e-12)
        #expect(abs(group.fractions[2] - 0.75 * 2 / 3) < 1e-12)
        // Clamped index: at the start or at the end.
        group.insert(ids[3], at: -4)
        group.insert(ids[4], at: 99)
        #expect(group.tabIDs == [ids[3], ids[0], ids[2], ids[1], ids[4]])
        #expect(abs(group.fractions.reduce(0, +) - 1) < 1e-9)
    }

    @Test func `inserting a member twice changes nothing`() {
        var group = SplitGroup(tabIDs: [ids[0], ids[1]], fractions: [0.3, 0.7])
        let before = group
        group.insert(ids[1], at: 0)
        #expect(group == before)
    }

    @Test func `removing a pane shares its width out in proportion`() {
        var group = SplitGroup(tabIDs: [ids[0], ids[1], ids[2]], fractions: [0.2, 0.3, 0.5])
        group.remove(ids[2])
        #expect(group.tabIDs == [ids[0], ids[1]])
        #expect(abs(group.fractions[0] - 0.4) < 1e-12)
        #expect(abs(group.fractions[1] - 0.6) < 1e-12)
        group.remove(ids[4])
        #expect(group.tabIDs.count == 2)
    }

    @Test func `set members keeps each fraction with its tab`() {
        var group = SplitGroup(tabIDs: [ids[0], ids[1], ids[2]], fractions: [0.2, 0.3, 0.5])
        group.setMembers([ids[2], ids[0], ids[1], ids[3]])
        #expect(group.tabIDs == [ids[2], ids[0], ids[1]])
        #expect(group.fractions == [0.5, 0.2, 0.3])
        group.setMembers([ids[2], ids[0]])
        #expect(group.tabIDs == [ids[2], ids[0]])
        #expect(abs(group.fractions[0] - 0.5 / 0.7) < 1e-12)
    }

    @Test func `neighbor is on the right, else on the left, else nil`() {
        let group = SplitGroup(tabIDs: [ids[0], ids[1], ids[2]])
        #expect(group.neighbor(of: ids[0]) == ids[1])
        #expect(group.neighbor(of: ids[1]) == ids[2])
        #expect(group.neighbor(of: ids[2]) == ids[1])
        #expect(group.neighbor(of: ids[3]) == nil)
        #expect(SplitGroup(tabIDs: [ids[0]]).neighbor(of: ids[0]) == nil)
        #expect(!group.isFull)
        #expect(SplitGroup(tabIDs: Array(ids.prefix(4))).isFull)
    }
}
