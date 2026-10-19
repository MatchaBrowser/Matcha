import Foundation

/// This Mac's changes (task 7.4, `SYNC.md` § 5): the current state compared, record by record, with what this Mac
/// had at its last sync (or with what it is about to send). A today tab that only changed page waits until it has
/// been stable for 5 seconds, 30 at most if it keeps changing (§ 2.4). Pure type.
nonisolated struct SyncChangeDetector: Sendable {
    static let stability: TimeInterval = 5
    static let maximumWait: TimeInterval = 30

    /// Change found: the new fields, nil for a deletion.
    struct Change: Equatable, Sendable {
        let id: UUID
        let fields: SyncFields?
    }

    /// Page of a today tab waiting to be stable.
    private struct Held: Sendable {
        var fields: SyncJSON
        var firstSeen: Date
        var lastChanged: Date
    }

    private var held: [UUID: Held] = [:]

    /// Changes in `snapshot` compared with `state`, sorted by type then by identifier, and the date at which to look
    /// at a waiting page again (nil if there is none).
    mutating func changes(in snapshot: [UUID: SyncFields], state: SyncState, now: Date) -> (changes: [Change], nextCheck: Date?) {
        var ids = Set(snapshot.keys)
        ids.formUnion(state.entries.compactMap { $0.value.local == nil ? nil : $0.key })
        ids.formUnion(state.pending.compactMap { $0.value.local == nil ? nil : $0.key })
        var changes: [Change] = []
        var nextCheck: Date?
        for id in ids {
            // Written by a newer version of Matcha: never modified here.
            if state.entries[id]?.remote?.isFromNewerVersion == true {
                continue
            }
            let current = snapshot[id]
            let currentJSON = current?.json
            let baseline = state.baseline(of: id)
            guard currentJSON != baseline else {
                held[id] = nil
                continue
            }
            if let rejected = state.rejected[id], rejected == currentJSON ?? .null {
                continue
            }
            if let currentJSON, isPageChange(current, from: baseline) {
                switch hold(id, fields: currentJSON, now: now) {
                case .send: break
                case let .wait(until): nextCheck = min(nextCheck ?? until, until)
                    continue
                }
            }
            held[id] = nil
            changes.append(Change(id: id, fields: current))
        }
        held = held.filter { ids.contains($0.key) }
        return (Self.sorted(changes, state: state), nextCheck)
    }

    private enum HoldDecision {
        case send
        case wait(until: Date)
    }

    /// Today tab where only the address, the title or the last use changed.
    private func isPageChange(_ current: SyncFields?, from baseline: SyncJSON?) -> Bool {
        guard case let .tab(now) = current, let baseline, case let .tab(before) = SyncFields(json: baseline, type: .tab) else {
            return false
        }
        return now.differsOnlyByPage(from: before)
    }

    private mutating func hold(_ id: UUID, fields: SyncJSON, now: Date) -> HoldDecision {
        let previous = held[id]
        let firstSeen = previous?.firstSeen ?? now
        let lastChanged = previous?.fields == fields ? previous?.lastChanged ?? now : now
        if now.timeIntervalSince(lastChanged) >= Self.stability || now.timeIntervalSince(firstSeen) >= Self.maximumWait {
            return .send
        }
        held[id] = Held(fields: fields, firstSeen: firstSeen, lastChanged: lastChanged)
        let stable = lastChanged.addingTimeInterval(Self.stability)
        return .wait(until: min(stable, firstSeen.addingTimeInterval(Self.maximumWait)))
    }

    private static func sorted(_ changes: [Change], state: SyncState) -> [Change] {
        func rank(_ change: Change) -> Int {
            change.fields?.type.applyRank ?? state.type(of: change.id).flatMap(SyncRecordType.init(rawValue:))?.applyRank ?? Int.max
        }
        return changes.sorted { (rank($0), $0.id.uuidString) < (rank($1), $1.id.uuidString) }
    }
}
