import Foundation

/// Where a new today tab goes, and which tab a window shows when its own leaves (review CO2: pure logic of
/// `TabManager`).
nonisolated extension SidebarLayout {
    /// Rank among the today tabs of a tab opened from `anchor`: after it (after its split if it has one) and after the
    /// tabs already opened from it (`isOpenedFromAnchor`), to keep the order of clicks; at the top without a today
    /// anchor.
    func todayInsertionIndex(after anchor: UUID?, isOpenedFromAnchor: (UUID) -> Bool) -> Int {
        guard let anchor, var index = today.firstIndex(of: split(containing: anchor)?.tabIDs.last ?? anchor) else {
            return 0
        }
        index += 1
        while index < today.count, isOpenedFromAnchor(today[index]) {
            index += 1
        }
        return index
    }

    /// Tab a window shows once the tabs `ids` left (this layout is the one after): `preferred` if it is still placed;
    /// otherwise, from rank `index` of the former today tabs `today`, the first one that is still a today tab after it,
    /// otherwise the last one before it. Nil from a pinned tab or a favorite (`index` nil).
    func nextSelection(from index: Int?, in today: [UUID], leaving ids: Set<UUID>, preferring preferred: UUID?) -> UUID? {
        if let preferred, !ids.contains(preferred), place(of: preferred) != nil {
            return preferred
        }
        guard let index else {
            return nil
        }
        func remains(_ id: UUID) -> Bool {
            !ids.contains(id) && place(of: id) == .today
        }
        return today[index...].first(where: remains) ?? today[..<index].last(where: remains)
    }
}
