import Foundation

/// Changements de ce Mac (tâche 7.4, `SYNC.md` § 5) : l'état actuel comparé, enregistrement par enregistrement, à ce que
/// ce Mac avait à sa dernière synchro (ou à ce qu'il s'apprête à envoyer). Un onglet du jour qui n'a changé que de page
/// attend d'être stable depuis 5 secondes, 30 au plus s'il change sans cesse (§ 2.4). Type pur.
nonisolated struct SyncChangeDetector: Sendable {
    static let stability: TimeInterval = 5
    static let maximumWait: TimeInterval = 30

    /// Changement trouvé : les nouveaux champs, nil pour une suppression.
    struct Change: Equatable, Sendable {
        let id: UUID
        let fields: SyncFields?
    }

    /// Page d'un onglet du jour qui attend d'être stable.
    private struct Held: Sendable {
        var fields: SyncJSON
        var firstSeen: Date
        var lastChanged: Date
    }

    private var held: [UUID: Held] = [:]

    /// Changements de `snapshot` par rapport à `state`, triés par type puis par identifiant, et la date à laquelle
    /// regarder de nouveau une page en attente (nil s'il n'y en a pas).
    mutating func changes(in snapshot: [UUID: SyncFields], state: SyncState, now: Date) -> (changes: [Change], nextCheck: Date?) {
        var ids = Set(snapshot.keys)
        ids.formUnion(state.entries.compactMap { $0.value.local == nil ? nil : $0.key })
        ids.formUnion(state.pending.compactMap { $0.value.local == nil ? nil : $0.key })
        var changes: [Change] = []
        var nextCheck: Date?
        for id in ids {
            // Écrit par une version plus récente de Matcha : jamais modifié ici.
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

    /// Onglet du jour dont seules l'adresse, le titre ou la dernière utilisation ont changé.
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
