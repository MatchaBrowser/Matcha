import Foundation

/// Place of a drop on the card: the left or right edge of a pane.
nonisolated struct SplitDropTarget: Equatable, Sendable {
    let paneIndex: Int
    let side: SplitSide

    /// Position of the new tab among the panes.
    var insertionIndex: Int {
        side == .leading ? paneIndex : paneIndex + 1
    }
}

/// Layout of a split's panes in the card: widths, dividers, drop zones. Pure type.
nonisolated enum SplitGeometry {
    /// Gap between two cards; equal to `BrowserWindowView.cardMargin` (checked by a test).
    static let gap = 8.0
    static let minimumPaneWidth = 200.0
    /// VoiceOver step: fraction of the panes' width.
    static let accessibilityStep = 0.05

    /// Widths in whole points of the `count` panes within `totalWidth`, gaps included: according to the fractions,
    /// each pane having at least `minimumPaneWidth` (taken from the others proportionally), or equal widths if space
    /// is lacking. The fractions are never rewritten.
    static func paneWidths(fractions: [Double], count: Int, totalWidth: Double) -> [Double] {
        guard count > 0 else {
            return []
        }
        let available = max(0, totalWidth - gap * Double(count - 1))
        let shares = SplitGroup.normalizedFractions(fractions, count: count)
        let floor = min(minimumPaneWidth, available / Double(count))
        var widths = shares.map { $0 * available }
        var isFixed = Array(repeating: false, count: count)
        for _ in 0 ..< count {
            let narrow = widths.indices.filter { !isFixed[$0] && widths[$0] < floor - 1e-6 }
            guard !narrow.isEmpty else {
                break
            }
            for index in narrow {
                isFixed[index] = true
                widths[index] = floor
            }
            let free = widths.indices.filter { !isFixed[$0] }
            let remaining = available - floor * Double(count - free.count)
            let shareSum = free.reduce(0) { $0 + shares[$1] }
            for index in free {
                widths[index] = shareSum > 0 ? remaining * shares[index] / shareSum : remaining / Double(free.count)
            }
        }
        // Rounded cumulative edges: no rounding error accumulates on a pane.
        var result: [Double] = []
        var sum = 0.0
        var previousEdge = 0.0
        for (index, width) in widths.enumerated() {
            sum += width
            let edge = index == count - 1 ? available : sum.rounded()
            result.append(edge - previousEdge)
            previousEdge = edge
        }
        return result
    }

    /// Left edge of each pane, gaps included.
    static func paneOrigins(widths: [Double]) -> [Double] {
        var origins: [Double] = []
        var origin = 0.0
        for width in widths {
            origins.append(origin)
            origin += width + gap
        }
        return origins
    }

    /// Fractions after dragging divider `index` (between panes `index` and `index + 1`) by `delta` points from
    /// `startWidths`: only these two panes change, without going below the minimum width.
    static func fractions(draggingDivider index: Int, by delta: Double, startWidths: [Double]) -> [Double] {
        guard index >= 0, index + 1 < startWidths.count else {
            return normalized(startWidths)
        }
        var widths = startWidths
        let pair = widths[index] + widths[index + 1]
        let lower = min(minimumPaneWidth, pair / 2)
        let leading = min(max(widths[index] + delta, lower), pair - lower)
        widths[index] = leading
        widths[index + 1] = pair - leading
        return normalized(widths)
    }

    /// Width of the drop strip of each edge of a pane: a quarter, between 60 and 180 pt, half at most.
    static func dropZoneWidth(forPaneWidth width: Double) -> Double {
        min(max(width * 0.25, 60), 180, width / 2)
    }

    /// Pane edge under the x-coordinate `position` (from the left edge of the panes); nil in the middle of a pane or
    /// in a gap.
    static func dropTarget(atX position: Double, widths: [Double]) -> SplitDropTarget? {
        for (index, origin) in paneOrigins(widths: widths).enumerated() {
            let width = widths[index]
            guard origin <= position, position < origin + width else {
                continue
            }
            let zone = dropZoneWidth(forPaneWidth: width)
            if position - origin <= zone {
                return SplitDropTarget(paneIndex: index, side: .leading)
            }
            if origin + width - position <= zone {
                return SplitDropTarget(paneIndex: index, side: .trailing)
            }
            return nil
        }
        return nil
    }

    private static func normalized(_ widths: [Double]) -> [Double] {
        let sum = widths.reduce(0, +)
        guard sum > 0, sum.isFinite else {
            return SplitGroup.equalFractions(count: widths.count)
        }
        return widths.map { $0 / sum }
    }
}
