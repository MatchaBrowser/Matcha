import Foundation
import OSLog

/// Envoi des changements en attente (`SYNC.md` § 5, étape 1).
extension SyncEngine {
    /// Tours d'envoi au plus dans un cycle : un conflit gagné par ce Mac repart au tour suivant.
    static let pushRounds = 4

    private enum Outcome {
        case done
        /// Le serveur a plus récent : son contenu s'applique ici.
        case remoteWins
        /// Ce Mac a plus récent : le changement repart sur la version du serveur.
        case retry
    }

    /// Envoie les changements en attente, par lots, parents d'abord.
    func push() async throws {
        for _ in 0 ..< Self.pushRounds {
            let ids = pendingIDs()
            guard !ids.isEmpty else {
                return
            }
            var winners: [UUID] = []
            var retries = false
            for start in stride(from: 0, to: ids.count, by: max(transport.maxChangesPerPush, 1)) {
                let batch = ids[start ..< min(start + max(transport.maxChangesPerPush, 1), ids.count)]
                let outgoing = batch.compactMap { id in
                    state.pending[id].map { SyncOutgoingChange(id: id, baseVersion: state.entries[id]?.version, content: $0.content) }
                }
                let results = try await transport.push(outgoing)
                for (change, result) in zip(outgoing, results) {
                    switch handle(result, for: change) {
                    case .done: break
                    case .remoteWins: winners.append(change.id)
                    case .retry: retries = true
                    }
                }
                save()
            }
            applyRemote(winners)
            save()
            if !retries {
                return
            }
        }
    }

    /// En attente, dans l'ordre d'application (parents d'abord), puis par identifiant.
    private func pendingIDs() -> [UUID] {
        func rank(_ id: UUID) -> Int {
            state.pending[id]?.content.recordType?.applyRank ?? Int.max
        }
        return state.pending.keys.sorted { (rank($0), $0.uuidString) < (rank($1), $1.uuidString) }
    }

    private func handle(_ result: SyncPushResult, for change: SyncOutgoingChange) -> Outcome {
        guard let pending = state.pending[change.id] else {
            return .done
        }
        switch result {
        case let .applied(version):
            state.entries[change.id] = SyncEntry(type: change.content.type, version: version, remote: change.content, local: pending.local)
            state.pending[change.id] = nil
            report.sent += 1
            return .done
        case let .conflict(current):
            report.conflicts += 1
            var entry = state.entries[change.id] ?? SyncEntry(type: change.content.type)
            entry.version = current.version
            guard let content = current.content else {
                // Illisible : jamais écrasé ; le changement de ce Mac est abandonné.
                Logger.sync.error("Conflit avec un enregistrement illisible : changement abandonné")
                entry.local = pending.local
                state.entries[change.id] = entry
                state.pending[change.id] = nil
                return .done
            }
            state.clock.observe(content.modifiedAt)
            entry.type = content.type
            entry.remote = content
            state.entries[change.id] = entry
            if content.isNewer(than: pending.content) || content.isFromNewerVersion {
                state.pending[change.id] = nil
                return .remoteWins
            }
            return .retry
        case let .rejected(code):
            Logger.sync.error("Changement refusé par le serveur : \(code, privacy: .public)")
            state.rejected[change.id] = pending.local ?? .null
            state.pending[change.id] = nil
            return .done
        }
    }
}
