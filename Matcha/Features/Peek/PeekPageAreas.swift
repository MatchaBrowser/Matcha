import SwiftUI

/// Pages of the displayed panes (without their address bar), reported by each `PageCard`: the peek is placed on
/// their union and puts a scrim over each one (task 4.4).
nonisolated struct PeekPageAreas: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] {
        []
    }

    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value += nextValue()
    }
}
