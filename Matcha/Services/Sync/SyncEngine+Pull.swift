import Foundation
import OSLog

/// Lecture des changements des autres Mac et application sur ce Mac (`SYNC.md` § 5, étape 2).
extension SyncEngine {
    /// Lit les changements depuis le curseur ; s'il a expiré, relit tout.
    func pull() async throws {
        do {
            try await readChanges(from: state.cursor)
        } catch SyncTransportError.cursorExpired {
            Logger.sync.notice("Curseur expiré : relecture complète")
            try await rereadEverything()
        }
    }

    /// Lit les pages depuis `cursor` en appliquant chacune ; renvoie les identifiants lus.
    @discardableResult
    func readChanges(from cursor: String?) async throws -> Set<UUID> {
        var cursor = cursor
        var seen: Set<UUID> = []
        while true {
            let page = try await transport.changes(since: cursor)
            var winners: [UUID] = []
            for record in page.records {
                seen.insert(record.id)
                if receive(record) {
                    winners.append(record.id)
                }
            }
            applyRemote(winners)
            cursor = page.cursor
            state.cursor = page.cursor
            save()
            if !page.hasMore {
                return seen
            }
        }
    }

    /// Retient `record` ; vrai s'il faut l'appliquer sur ce Mac (pas un écho de ce Mac ni une version déjà dépassée,
    /// pas plus ancien que son changement en attente).
    private func receive(_ record: SyncRemoteRecord) -> Bool {
        var entry = state.entries[record.id] ?? SyncEntry(type: record.content?.type ?? "")
        if let known = entry.version, record.version <= known {
            return false
        }
        entry.version = record.version
        guard let content = record.content else {
            Logger.sync.error("Enregistrement illisible ignoré")
            state.entries[record.id] = entry
            return false
        }
        state.clock.observe(content.modifiedAt)
        entry.type = content.type
        entry.remote = content
        state.entries[record.id] = entry
        if let pending = state.pending[record.id] {
            guard content.isNewer(than: pending.content) || content.isFromNewerVersion else {
                // Le changement de ce Mac est plus récent : il repartira sur cette version.
                return false
            }
            state.pending[record.id] = nil
        }
        return true
    }

    /// Curseur expiré : relit tout ; un enregistrement de ce Mac absent du serveur et sans changement en attente est
    /// supprimé ici.
    private func rereadEverything() async throws {
        state.cursor = nil
        let seen = try await readChanges(from: nil)
        var deletions: [SyncLocalChange] = []
        for (id, entry) in state.entries where !seen.contains(id) {
            if state.pending[id] != nil {
                state.entries[id]?.version = nil
                continue
            }
            if entry.local != nil, let type = SyncRecordType(rawValue: entry.type) {
                deletions.append(.delete(id, type))
            }
            state.entries[id] = nil
        }
        _ = store.apply(SyncLocalChange.ordered(deletions))
        report.received += deletions.count
    }

    /// Applique sur ce Mac le contenu du serveur de `ids`, et retente ce qui attendait son parent. Les champs de ce Mac
    /// après application deviennent la référence des changements suivants : rien ne repart en écho.
    func applyRemote(_ ids: [UUID]) {
        let retried = state.entries.compactMap { $0.value.isWaiting ? $0.key : nil }
        var changes: [SyncLocalChange] = []
        for id in Set(ids).union(retried) {
            guard let remote = state.entries[id]?.remote else {
                continue
            }
            if remote.deleted {
                if let type = remote.recordType {
                    changes.append(.delete(id, type))
                }
            } else if let fields = remote.readableFields {
                changes.append(.upsert(id, fields))
            } else {
                // Type, format ou valeur inconnus : ignoré, sans écraser ce qu'a ce Mac.
                Logger.sync.notice("Enregistrement d'un format inconnu ignoré")
            }
        }
        guard !changes.isEmpty else {
            return
        }
        let waiting = store.apply(SyncLocalChange.ordered(changes))
        let snapshot = store.snapshot()
        for change in changes {
            let isWaiting = waiting.contains(change.id)
            state.entries[change.id]?.isWaiting = isWaiting
            state.entries[change.id]?.local = isWaiting ? nil : snapshot[change.id]?.json
            if !isWaiting {
                report.received += 1
            }
        }
    }
}
