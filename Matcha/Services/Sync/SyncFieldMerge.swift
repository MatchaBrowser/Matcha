import Foundation

/// Content sent for a modification made on this Mac (`SYNC.md` § 5): the last accepted content, where only the fields
/// changed on this Mac since its last sync are replaced, entry by entry for an extension's permission lists. A value
/// received and not applied here (an update not installed, a permission, an `allow`) leaves again as it is, and so do
/// the fields unknown to this version. A field emptied here (absent: `null`) is removed. Pure type.
nonisolated enum SyncFieldMerge {
    /// Fields compared entry by entry: name or pattern → expiration date.
    static let entryByEntryKeys: Set<String> = ["grantedPermissions", "deniedPermissions", "grantedMatchPatterns", "deniedMatchPatterns"]

    /// `remote` with the changes from `baseline` to `local`; without a baseline (the record wasn't on this Mac), all
    /// of `local` replaces `remote`.
    static func merged(remote: SyncJSON, local: SyncJSON, baseline: SyncJSON?) -> SyncJSON {
        guard let baseline else {
            return .object(remote.objectValue.merging(local.objectValue) { _, mine in mine })
        }
        var result = remote.objectValue
        let mine = local.objectValue
        let before = baseline.objectValue
        for key in Set(mine.keys).union(before.keys) where mine[key] != before[key] {
            if entryByEntryKeys.contains(key) {
                result[key] = .object(mergedEntries(
                    remote: result[key]?.objectValue ?? [:],
                    local: mine[key]?.objectValue ?? [:],
                    baseline: before[key]?.objectValue ?? [:],
                ))
            } else {
                result[key] = mine[key]
            }
        }
        return .object(result)
    }

    private static func mergedEntries(
        remote: [String: SyncJSON],
        local: [String: SyncJSON],
        baseline: [String: SyncJSON],
    ) -> [String: SyncJSON] {
        var result = remote
        for name in Set(local.keys).union(baseline.keys) where local[name] != baseline[name] {
            result[name] = local[name]
        }
        return result
    }
}
