import Foundation

/// This Mac's changes (`SYNC.md` § 5): the current state compared, record by record, with what this Mac had at its
/// last sync (or with what it is about to send). Records kept as they are (unreadable, newer format) and this Mac's
/// local records are never sent. A modification of this Mac's tabs (`deviceTabs`) waits until it has been stable for
/// 5 seconds, a minute at most if it keeps changing, and never leaves less than a minute after the previous one
/// (§ 2.4). Pure type.
nonisolated struct SyncChangeDetector: Sendable {
    static let stability: TimeInterval = 5
    static let maximumWait: TimeInterval = 60
    static let minimumInterval: TimeInterval = 60

    /// Change found: the new fields, nil for a deletion.
    struct Change: Equatable, Sendable {
        let id: UUID
        let fields: SyncFields?
    }

    /// Modification of this Mac's tabs waiting to leave.
    private struct Held: Sendable {
        var fields: SyncJSON
        var firstSeen: Date
        var lastChanged: Date
    }

    private var held: [UUID: Held] = [:]
    /// Last sending of this Mac's tabs, during this launch.
    private var lastSent: [UUID: Date] = [:]

    /// Changes in `snapshot` compared with `state`, sorted by type then by identifier, and the date at which to look
    /// at a waiting change again (nil if there is none). `encoded`: the snapshot's fields already as JSON
    /// (`SyncJSONCache`, review SY13); without it, each record is encoded here.
    mutating func changes(
        in snapshot: [UUID: SyncFields],
        encoded: [UUID: SyncJSON?]? = nil,
        exceptions: SyncLocalExceptions = SyncLocalExceptions(),
        state: SyncState,
        now: Date,
    ) -> (changes: [Change], nextCheck: Date?) {
        var ids = Set(snapshot.keys)
        ids.formUnion(state.entries.compactMap { $0.value.local == nil ? nil : $0.key })
        ids.formUnion(state.pending.compactMap { $0.value.local == nil ? nil : $0.key })
        ids.subtract(exceptions.localRecords)
        var changes: [Change] = []
        var nextCheck: Date?
        for id in ids {
            // Unreadable, or written by a newer version of Matcha: never modified here.
            if state.entries[id]?.isIgnored == true {
                continue
            }
            let current = snapshot[id]
            let currentJSON: SyncJSON? = if let encoded, current != nil {
                encoded[id].flatMap(\.self)
            } else {
                current?.encodedJSON
            }
            // Fields that can't be encoded: neither sent as empty nor taken for a deletion (review SY28).
            if current != nil, currentJSON == nil {
                continue
            }
            let baseline = state.baseline(of: id)
            guard currentJSON != baseline else {
                held[id] = nil
                continue
            }
            if let rejected = state.rejected[id], rejected.local == currentJSON ?? .null {
                continue
            }
            if case .deviceTabs = current, baseline != nil, let currentJSON {
                if let until = wait(id, fields: currentJSON, now: now) {
                    nextCheck = min(nextCheck ?? until, until)
                    continue
                }
                lastSent[id] = now
            }
            held[id] = nil
            changes.append(Change(id: id, fields: current))
        }
        held = held.filter { ids.contains($0.key) }
        return (Self.sorted(changes, state: state), nextCheck)
    }

    /// Date until which the modification `fields` of this Mac's tabs waits; nil: it leaves now.
    private mutating func wait(_ id: UUID, fields: SyncJSON, now: Date) -> Date? {
        let previous = held[id]
        let firstSeen = previous?.firstSeen ?? now
        let lastChanged = previous?.fields == fields ? previous?.lastChanged ?? now : now
        let settled = min(lastChanged.addingTimeInterval(Self.stability), firstSeen.addingTimeInterval(Self.maximumWait))
        let allowed = lastSent[id].map { $0.addingTimeInterval(Self.minimumInterval) } ?? now
        let until = max(settled, allowed)
        if until <= now {
            return nil
        }
        held[id] = Held(fields: fields, firstSeen: firstSeen, lastChanged: lastChanged)
        return until
    }

    private static func sorted(_ changes: [Change], state: SyncState) -> [Change] {
        func rank(_ change: Change) -> Int {
            change.fields?.type.applyRank ?? state.type(of: change.id).flatMap(SyncRecordType.init(rawValue:))?.applyRank ?? Int.max
        }
        return changes.sorted { (rank($0), $0.id.uuidString) < (rank($1), $1.id.uuidString) }
    }
}
