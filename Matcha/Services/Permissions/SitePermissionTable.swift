import Foundation

/// All the remembered decisions, in memory: lookup, change, removal (task 5.2). Pure type, without saving;
/// `SitePermissionStore` saves it.
nonisolated struct SitePermissionTable: Sendable {
    private(set) var entries: [SitePermissionEntry.Key: SitePermissionEntry] = [:]

    /// For the same key, the most recent decision wins.
    init(_ entries: [SitePermissionEntry] = []) {
        for entry in entries where self.entries[entry.key].map({ $0.date <= entry.date }) ?? true {
            self.entries[entry.key] = entry
        }
    }

    /// Decisions of the profile for this origin, by permission.
    func decisions(for origin: SiteOrigin, profileID: UUID?) -> [SitePermissionKind: SitePermissionDecision] {
        var decisions: [SitePermissionKind: SitePermissionDecision] = [:]
        for kind in SitePermissionKind.allCases {
            decisions[kind] = entries[.init(profileID: profileID, origin: origin, kind: kind)]?.decision
        }
        return decisions
    }

    /// Remembers `decision`, or forgets it if it is nil.
    mutating func set(
        _ decision: SitePermissionDecision?,
        for kind: SitePermissionKind,
        origin: SiteOrigin,
        profileID: UUID?,
        date: Date = .now,
    ) {
        let key = SitePermissionEntry.Key(profileID: profileID, origin: origin, kind: kind)
        entries[key] = decision.map { SitePermissionEntry(key: key, decision: $0, date: date) }
    }

    /// Forgets all the decisions of a profile (deleted profile).
    mutating func removeAll(profileID: UUID?) {
        entries = entries.filter { $0.key.profileID != profileID }
    }

    /// Order of the settings: by website (displayed host, then key), then permission in the order of
    /// `SitePermissionKind`, then profile.
    var sortedEntries: [SitePermissionEntry] {
        let kinds = SitePermissionKind.allCases
        return entries.values.sorted { lhs, rhs in
            let left = (lhs.origin.displayHost, lhs.origin.key, kinds.firstIndex(of: lhs.kind) ?? 0, lhs.profileID?.uuidString ?? "")
            let right = (rhs.origin.displayHost, rhs.origin.key, kinds.firstIndex(of: rhs.kind) ?? 0, rhs.profileID?.uuidString ?? "")
            return left < right
        }
    }
}
