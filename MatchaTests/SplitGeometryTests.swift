import Foundation
@testable import Matcha
import Testing

struct SplitGeometryTests {
    private let gap = SplitGeometry.gap

    @Test(arguments: [(1, 800.0), (2, 1001.0), (3, 1500.0), (4, 3000.0)])
    func `widths follow the fractions and fill the width in whole points`(count: Int, width: Double) {
        let fractions = Array([0.1, 0.2, 0.3, 0.4].prefix(count))
        let shares = SplitGroup.normalizedFractions(fractions, count: count)
        let widths = SplitGeometry.paneWidths(fractions: fractions, count: count, totalWidth: width)
        let available = width - gap * Double(count - 1)
        #expect(widths.count == count)
        #expect(widths.reduce(0, +) + gap * Double(count - 1) == width)
        #expect(widths.allSatisfy { $0 == $0.rounded() })
        for (index, paneWidth) in widths.enumerated() {
            #expect(abs(paneWidth - shares[index] * available) <= 1)
        }
    }

    @Test func `narrow panes are raised to the minimum, taken from the others in proportion`() {
        let widths = SplitGeometry.paneWidths(fractions: [0.1, 0.2, 0.3, 0.4], count: 4, totalWidth: 1000)
        #expect(widths == [200, 200, 247, 329])
        #expect(widths.reduce(0, +) + 3 * gap == 1000)
    }

    @Test func `too narrow a card gives equal widths`() {
        let widths = SplitGeometry.paneWidths(fractions: [0.6, 0.2, 0.2], count: 3, totalWidth: 500)
        #expect(widths.reduce(0, +) == 484)
        #expect(widths.allSatisfy { abs($0 - 484 / 3.0) <= 1 })
        // Rien ne déborde, même sans place du tout.
        #expect(SplitGeometry.paneWidths(fractions: [], count: 2, totalWidth: 4) == [0, 0])
        #expect(SplitGeometry.paneWidths(fractions: [0.5], count: 0, totalWidth: 500).isEmpty)
    }

    @Test func `fractions survive a window resize`() {
        let fractions = [0.2, 0.8]
        #expect(SplitGeometry.paneWidths(fractions: fractions, count: 2, totalWidth: 608) == [200, 400])
        #expect(SplitGeometry.paneWidths(fractions: fractions, count: 2, totalWidth: 2008) == [400, 1600])
    }

    @Test func `dragging a divider changes only its two panes`() {
        let fractions = SplitGeometry.fractions(draggingDivider: 0, by: 50, startWidths: [300, 300, 400])
        #expect(fractions == [0.35, 0.25, 0.4])
        let second = SplitGeometry.fractions(draggingDivider: 1, by: -20, startWidths: [300, 300, 400])
        #expect(second == [0.3, 0.28, 0.42])
    }

    @Test func `dragging stops at the minimum width on both sides`() {
        #expect(SplitGeometry.fractions(draggingDivider: 0, by: 1000, startWidths: [300, 300]) == [400 / 600.0, 200 / 600.0])
        #expect(SplitGeometry.fractions(draggingDivider: 0, by: -1000, startWidths: [300, 300]) == [200 / 600.0, 400 / 600.0])
        // Deux panneaux déjà trop étroits : ils restent égaux.
        #expect(SplitGeometry.fractions(draggingDivider: 0, by: 40, startWidths: [150, 150]) == [0.5, 0.5])
    }

    @Test func `an out of range divider returns the widths normalized`() {
        #expect(SplitGeometry.fractions(draggingDivider: 2, by: 10, startWidths: [100, 300, 600]) == [0.1, 0.3, 0.6])
        #expect(SplitGeometry.fractions(draggingDivider: -1, by: 10, startWidths: [200, 200]) == [0.5, 0.5])
        #expect(SplitGeometry.fractions(draggingDivider: 0, by: 10, startWidths: [0, 0]) == [0.5, 0.5])
    }

    @Test func `origins add the gaps`() {
        #expect(SplitGeometry.paneOrigins(widths: [100, 200, 300]) == [0, 100 + gap, 300 + 2 * gap])
        #expect(SplitGeometry.paneOrigins(widths: []).isEmpty)
    }

    @Test func `drop zone is a quarter of the pane between 60 and 180 pt and at most half`() {
        #expect(SplitGeometry.dropZoneWidth(forPaneWidth: 400) == 100)
        #expect(SplitGeometry.dropZoneWidth(forPaneWidth: 200) == 60)
        #expect(SplitGeometry.dropZoneWidth(forPaneWidth: 1000) == 180)
        #expect(SplitGeometry.dropZoneWidth(forPaneWidth: 100) == 50)
    }

    @Test func `drop target is a pane edge, nil in the middle and in a gap`() {
        let widths = [400.0, 400.0]
        func target(_ position: Double) -> SplitDropTarget? {
            SplitGeometry.dropTarget(atX: position, widths: widths)
        }
        #expect(target(0) == SplitDropTarget(paneIndex: 0, side: .leading))
        #expect(target(100) == SplitDropTarget(paneIndex: 0, side: .leading))
        #expect(target(101) == nil)
        #expect(target(300) == SplitDropTarget(paneIndex: 0, side: .trailing))
        #expect(target(400) == nil)
        #expect(target(400 + gap - 1) == nil)
        #expect(target(400 + gap) == SplitDropTarget(paneIndex: 1, side: .leading))
        #expect(target(800 + gap - 1) == SplitDropTarget(paneIndex: 1, side: .trailing))
        #expect(target(800 + gap) == nil)
        #expect(target(-1) == nil)
        #expect(SplitDropTarget(paneIndex: 0, side: .trailing).insertionIndex == 1)
        #expect(SplitDropTarget(paneIndex: 1, side: .leading).insertionIndex == 1)
        #expect(SplitDropTarget(paneIndex: 1, side: .trailing).insertionIndex == 2)
    }

    @MainActor
    @Test func `gap equals the card margin`() {
        #expect(SplitGeometry.gap == BrowserWindowView.cardMargin)
    }
}
