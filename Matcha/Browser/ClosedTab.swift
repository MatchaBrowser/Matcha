import Foundation

/// A tab the user closed (audit H2), as ⇧⌘T brings it back: its page and history (`StoredTab`), its section and its
/// rank there. Pure type.
nonisolated struct ClosedTab: Sendable {
    let stored: StoredTab
    let place: TabPlace
    /// Rank among the today tabs; nil for a pinned tab or a favorite (it comes back at the end of its section).
    let todayIndex: Int?
}

/// Tabs closed together: one tab (⌘W), or all those of “Clear” or “Close Other Tabs”, which come back together.
/// Pure type.
nonisolated struct ClosedTabGroups: Sendable {
    /// Groups kept, the oldest go first.
    static let maximumCount = 20

    private(set) var groups: [[ClosedTab]] = []

    var isEmpty: Bool {
        groups.isEmpty
    }

    /// Number of tabs that ⇧⌘T would bring back.
    var lastCount: Int {
        groups.last?.count ?? 0
    }

    mutating func append(_ group: [ClosedTab]) {
        guard !group.isEmpty else {
            return
        }
        groups.append(group)
        if groups.count > Self.maximumCount {
            groups.removeFirst(groups.count - Self.maximumCount)
        }
    }

    mutating func popLast() -> [ClosedTab]? {
        groups.popLast()
    }
}
