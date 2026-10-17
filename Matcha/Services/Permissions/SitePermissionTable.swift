import Foundation

/// Décision retenue d'un profil pour une origine et une permission.
nonisolated struct SitePermissionEntry: Hashable, Identifiable, Sendable {
    struct Key: Hashable, Sendable {
        let profileID: UUID?
        let origin: SiteOrigin
        let kind: SitePermissionKind
    }

    let key: Key
    var decision: SitePermissionDecision
    var date: Date

    var id: Key {
        key
    }

    var profileID: UUID? {
        key.profileID
    }

    var origin: SiteOrigin {
        key.origin
    }

    var kind: SitePermissionKind {
        key.kind
    }
}

/// Toutes les décisions retenues, en mémoire : recherche, modification, oubli (tâche 5.2). Type pur, sans
/// enregistrement ; `SitePermissionStore` l'enregistre.
nonisolated struct SitePermissionTable: Sendable {
    private(set) var entries: [SitePermissionEntry.Key: SitePermissionEntry] = [:]

    /// Pour une même clé, la décision la plus récente l'emporte.
    init(_ entries: [SitePermissionEntry] = []) {
        for entry in entries where self.entries[entry.key].map({ $0.date <= entry.date }) ?? true {
            self.entries[entry.key] = entry
        }
    }

    /// Décisions du profil pour cette origine, par permission.
    func decisions(for origin: SiteOrigin, profileID: UUID?) -> [SitePermissionKind: SitePermissionDecision] {
        var decisions: [SitePermissionKind: SitePermissionDecision] = [:]
        for kind in SitePermissionKind.allCases {
            decisions[kind] = entries[.init(profileID: profileID, origin: origin, kind: kind)]?.decision
        }
        return decisions
    }

    /// Retient `decision`, ou l'oublie si elle est nil.
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

    /// Oublie toutes les décisions d'un profil (profil supprimé).
    mutating func removeAll(profileID: UUID?) {
        entries = entries.filter { $0.key.profileID != profileID }
    }

    /// Ordre des réglages : par site (hôte affiché, puis clé), puis permission dans l'ordre de `SitePermissionKind`,
    /// puis profil.
    var sortedEntries: [SitePermissionEntry] {
        let kinds = SitePermissionKind.allCases
        return entries.values.sorted { lhs, rhs in
            let left = (lhs.origin.displayHost, lhs.origin.key, kinds.firstIndex(of: lhs.kind) ?? 0, lhs.profileID?.uuidString ?? "")
            let right = (rhs.origin.displayHost, rhs.origin.key, kinds.firstIndex(of: rhs.kind) ?? 0, rhs.profileID?.uuidString ?? "")
            return left < right
        }
    }
}
