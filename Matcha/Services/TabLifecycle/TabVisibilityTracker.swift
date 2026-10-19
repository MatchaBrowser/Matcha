import Foundation

/// Since when each tab has been hidden (task 5.6). “Visible”: displayed in an open window, selected tab or pane of its
/// split, in the displayed Space; the rest is hidden, including the selected tab of a Space that is not displayed.
/// Updated at each change of what is displayed, with the time of the change.
nonisolated struct TabVisibilityTracker: Sendable {
    /// Hidden tabs and the time at which they left the screen (or were first seen hidden).
    private(set) var hiddenSince: [UUID: Date] = [:]

    /// `visible`: displayed tabs; `present`: all open tabs. A tab that leaves the screen is hidden since `now`; a
    /// hidden tab keeps its date; a closed tab is forgotten.
    mutating func update(visible: Set<UUID>, present: Set<UUID>, now: Date) {
        var next: [UUID: Date] = [:]
        for id in present where !visible.contains(id) {
            next[id] = hiddenSince[id] ?? now
        }
        hiddenSince = next
    }

    func hiddenSince(_ id: UUID) -> Date? {
        hiddenSince[id]
    }
}
