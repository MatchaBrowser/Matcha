import Foundation

/// Merges two versions of an item without losing a secret (`VAULT.md` § 5.3 and § 5.4). Pure type.
nonisolated enum VaultMerge {
    /// Field by field, against the verified version both started from: what changed on one side only takes that
    /// value; what changed on both takes the value of the more recent version, and a losing secret goes into the
    /// history. Lists of entries with an `id` merge entry by entry. The result is dated by the caller.
    static func merged(local: VaultItemContent, remote: VaultItemContent, base: VaultItemContent) -> VaultItemContent {
        let localWins = local.overview.isNewer(than: remote.overview)
        let (winner, loser) = localWins ? (local, remote) : (remote, local)
        var result = winner
        result.overview = mergedOverview(local: local.overview, remote: remote.overview, base: base.overview, localWins: localWins)
        result.details.credentials = mergedEntries(
            Sides(local: local.details.credentials, remote: remote.details.credentials, base: base.details.credentials),
            localWins,
        )
        result.details.fields = mergedEntries(
            Sides(local: local.details.fields, remote: remote.details.fields, base: base.details.fields),
            localWins,
        )
        result.details.files = mergedEntries(
            Sides(local: local.details.files, remote: remote.details.files, base: base.details.files),
            localWins,
        )
        result.details.notes = pick(local.details.notes, remote.details.notes, base.details.notes, localWins)
        result.details.history = []
        for entry in local.details.history + remote.details.history {
            result.addHistory(entry)
        }
        result.keepHistory(of: loser)
        result.keepHistory(of: winner)
        return result
    }

    /// Without a common version (reconciliation, `VAULT.md` § 5.3): the more recent version whole, and each secret of
    /// the other that differs goes into its history.
    static func reconciled(_ first: VaultItemContent, _ second: VaultItemContent) -> VaultItemContent {
        let (winner, loser) = first.overview.isNewer(than: second.overview) ? (first, second) : (second, first)
        var result = winner
        for entry in loser.details.history {
            result.addHistory(entry)
        }
        result.keepHistory(of: loser)
        return result
    }

    // MARK: Fields

    /// Key by key, against the base: the values changed on one side only are kept from both.
    private static func mergedKeys(_ local: VaultEntry, _ remote: VaultEntry, _ base: VaultEntry, _ localWins: Bool) -> VaultEntry {
        var result = localWins ? local : remote
        for key in Set(local.keys + remote.keys + base.keys) {
            result.set(key, json: pick(local.value(key), remote.value(key), base.value(key), localWins))
        }
        return result
    }

    private static func pick<Value: Equatable>(_ local: Value, _ remote: Value, _ base: Value, _ localWins: Bool) -> Value {
        switch (local != base, remote != base) {
        case (true, false): local
        case (false, true): remote
        case (true, true): localWins ? local : remote
        case (false, false): base
        }
    }

    private static func mergedOverview(local: VaultOverview, remote: VaultOverview, base: VaultOverview, localWins: Bool) -> VaultOverview {
        var result = localWins ? local : remote
        result.title = pick(local.title, remote.title, base.title, localWins)
        result.subtitle = pick(local.subtitle, remote.subtitle, base.subtitle, localWins)
        result.favorite = pick(local.favorite, remote.favorite, base.favorite, localWins)
        result.tags = pick(local.tags, remote.tags, base.tags, localWins)
        result.urls = pick(local.urls, remote.urls, base.urls, localWins)
        result.match = pick(local.match, remote.match, base.match, localWins)
        result.trashedAt = pick(local.trashedAt, remote.trashedAt, base.trashedAt, localWins)
        result.category = pick(local.category, remote.category, base.category, localWins)
        return result
    }

    /// Entry by entry, paired by `id`, in the order of the winner then the entries the other added: an entry added on
    /// one side is kept, an entry removed on one side and changed on the other is kept.
    /// The three versions of a list of entries.
    private struct Sides {
        let local: [VaultEntry]
        let remote: [VaultEntry]
        let base: [VaultEntry]
    }

    private static func mergedEntries(_ sides: Sides, _ localWins: Bool) -> [VaultEntry] {
        let (local, remote, base) = (sides.local, sides.remote, sides.base)
        let byID = { (entries: [VaultEntry]) in Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
        let (localByID, remoteByID, baseByID) = (byID(local), byID(remote), byID(base))
        let order = (localWins ? local + remote : remote + local).map(\.id)
        var seen: Set<String> = []
        var result: [VaultEntry] = []
        for id in order where seen.insert(id).inserted {
            if let entry = mergedEntry(localByID[id], remoteByID[id], baseByID[id], localWins) {
                result.append(entry)
            }
        }
        return result
    }

    private static func mergedEntry(_ local: VaultEntry?, _ remote: VaultEntry?, _ base: VaultEntry?, _ localWins: Bool) -> VaultEntry? {
        switch (local, remote) {
        case let (local?, remote?):
            mergedKeys(local, remote, base ?? VaultEntry(), localWins)
        case let (local?, nil):
            // Removed there: kept if changed here, or if it was never there (added here).
            base == nil || base != local ? local : nil
        case let (nil, remote?):
            base == nil || base != remote ? remote : nil
        case (nil, nil):
            nil
        }
    }
}
