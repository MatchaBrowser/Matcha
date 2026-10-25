import Foundation

/// Today tabs of the versions before 2026-10-25 (`SYNC.md` § 2.4): they traveled one by one, as `tab` records with
/// `place: today`. They now stay on each Mac. This version neither applies, sends nor deletes these records: deleting
/// one would close the tab on a Mac still on an older version. Pure type.
nonisolated enum SyncLegacyTodayTabs {
    /// True if `fields`, of a record of type `type`, are those of a today tab.
    static func isTodayTab(_ fields: SyncJSON?, type: String?) -> Bool {
        type == SyncRecordType.tab.rawValue && fields?.objectValue["place"] == .string(SyncTabPlace.today.rawValue)
    }
}

nonisolated extension SyncState {
    /// Forgets the today tabs this Mac had sent or applied: out of its snapshot now, they would otherwise leave as
    /// deletions. Their last accepted content stays, against going back (`SYNC.md` § 2.3); a today tab pinned here
    /// later is then sent as a modification of its record.
    mutating func forgetTodayTabs() {
        for (id, entry) in entries where SyncLegacyTodayTabs.isTodayTab(entry.local, type: entry.type) {
            entries[id]?.local = nil
            // A deletion waiting to leave: the today tab was closed here.
            if let change = pending[id], change.local == nil {
                pending[id] = nil
            }
        }
        pending = pending.filter { !SyncLegacyTodayTabs.isTodayTab($0.value.local, type: $0.value.content.type) }
        rejected = rejected.filter { !SyncLegacyTodayTabs.isTodayTab($0.value.local, type: type(of: $0.key)) }
    }
}
