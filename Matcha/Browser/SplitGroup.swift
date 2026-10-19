import Foundation

/// Side of a pane where the dropped tab goes.
nonisolated enum SplitSide: Equatable, Sendable {
    case leading
    case trailing
}

/// A tab facing the displayed content: it can join it, the split is full, or it is impossible.
nonisolated enum SplitAvailability: Equatable, Sendable {
    case allowed
    case full
    case unavailable
}

/// Split view: 2 to 4 tabs side by side, from left to right (their order in the sidebar), with the width share
/// of each one. Pure type.
nonisolated struct SplitGroup: Equatable, Sendable, Identifiable {
    static let paneCount = 2 ... 4

    let id: UUID
    private(set) var tabIDs: [UUID]
    /// Width share of each pane, in the order of `tabIDs`; they sum to 1.
    private(set) var fractions: [Double]

    /// A duplicated tab is kept only once; invalid shares become equal shares.
    init(id: UUID = UUID(), tabIDs: [UUID], fractions: [Double] = []) {
        self.id = id
        var seen: Set<UUID> = []
        let unique = tabIDs.indices.filter { seen.insert(tabIDs[$0]).inserted }
        self.tabIDs = unique.map { tabIDs[$0] }
        let kept = fractions.count == tabIDs.count ? unique.map { fractions[$0] } : fractions
        self.fractions = Self.normalizedFractions(kept, count: self.tabIDs.count)
    }

    var isFull: Bool {
        tabIDs.count >= Self.paneCount.upperBound
    }

    func contains(_ tabID: UUID) -> Bool {
        tabIDs.contains(tabID)
    }

    func index(of tabID: UUID) -> Int? {
        tabIDs.firstIndex(of: tabID)
    }

    /// Neighboring pane: on the right, otherwise on the left; nil outside the group or when alone.
    func neighbor(of tabID: UUID) -> UUID? {
        guard let index = index(of: tabID), tabIDs.count > 1 else {
            return nil
        }
        return index + 1 < tabIDs.count ? tabIDs[index + 1] : tabIDs[index - 1]
    }

    /// Inserts at position `index` (clamped); the new pane gets 1/(n+1), the others × n/(n+1).
    /// No effect if it is already there.
    mutating func insert(_ tabID: UUID, at index: Int) {
        guard !contains(tabID) else {
            return
        }
        let count = Double(tabIDs.count)
        var shares = fractions.map { $0 * count / (count + 1) }
        let position = min(max(index, 0), tabIDs.count)
        tabIDs.insert(tabID, at: position)
        shares.insert(1 / (count + 1), at: position)
        fractions = Self.normalizedFractions(shares, count: tabIDs.count)
    }

    /// Removes the pane; the other shares are brought back to a sum of 1.
    mutating func remove(_ tabID: UUID) {
        guard let index = index(of: tabID) else {
            return
        }
        tabIDs.remove(at: index)
        var shares = fractions
        shares.remove(at: index)
        fractions = Self.normalizedFractions(shares, count: tabIDs.count)
    }

    /// Keeps `ids` (current members; the others are ignored) in that order; each share follows its tab.
    mutating func setMembers(_ ids: [UUID]) {
        let shares = Dictionary(zip(tabIDs, fractions)) { first, _ in first }
        var seen: Set<UUID> = []
        let members = ids.filter { shares[$0] != nil && seen.insert($0).inserted }
        tabIDs = members
        fractions = Self.normalizedFractions(members.compactMap { shares[$0] }, count: members.count)
    }

    mutating func setFractions(_ fractions: [Double]) {
        self.fractions = Self.normalizedFractions(fractions, count: tabIDs.count)
    }

    static func equalFractions(count: Int) -> [Double] {
        count > 0 ? Array(repeating: 1 / Double(count), count: count) : []
    }

    /// `count` finite numbers > 0: unchanged if their sum is 1 within 1e-9, otherwise divided by their sum;
    /// anything else (NaN, ≤ 0, wrong count): equal shares. `count` ≤ 0: [].
    static func normalizedFractions(_ fractions: [Double], count: Int) -> [Double] {
        guard count > 0 else {
            return []
        }
        guard fractions.count == count, fractions.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return equalFractions(count: count)
        }
        let sum = fractions.reduce(0, +)
        guard sum.isFinite, sum > 0 else {
            return equalFractions(count: count)
        }
        return abs(sum - 1) <= 1e-9 ? fractions : fractions.map { $0 / sum }
    }
}
