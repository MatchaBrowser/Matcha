import Foundation
import OSLog

/// Applying the received contents on this Mac (`SYNC.md` § 2.3 and § 5, step 2).
extension SyncEngine {
    /// What applying one record does: the change written here, whether its reference stays (a change made here since
    /// this cycle read this Mac, sent next), and the keys its reference keeps (a deleted parent).
    private struct Application {
        var change: SyncLocalChange?
        var keepsBaseline = false
        var restoredKeys: [String: SyncJSON] = [:]
    }

    /// Adds `ids` to the received contents to apply (`SyncState.toApply`), then applies them all: they leave the list
    /// once applied, never before (review SY6).
    func applyAccepted(_ ids: [UUID] = []) throws {
        state.toApply.formUnion(ids)
        guard !state.toApply.isEmpty else {
            return
        }
        let accepted = state.toApply.sorted { $0.uuidString < $1.uuidString }
        try applyRemote(accepted)
        state.toApply.subtract(accepted)
    }

    /// Applies the accepted content of `ids` on this Mac. This Mac's fields after applying become the reference for
    /// the next changes: nothing is sent back as an echo. An unreadable record, or one from a newer version, is
    /// never applied. A record changed here since this cycle read this Mac keeps that change, sent next (review SY23);
    /// a record whose parent was deleted goes to the root of its Space, or is deleted (`SYNC.md` § 2.3, review SY32).
    func applyRemote(_ ids: [UUID]) throws {
        try Task.checkCancellation()
        var unique = Set<UUID>()
        let candidates = ids.filter { unique.insert($0).inserted }
        // This Mac as read again now, to compare with what this cycle detected.
        let before = detectedSnapshot == nil || candidates.isEmpty ? nil : try store.snapshot()
        var applications: [UUID: Application] = [:]
        for id in candidates {
            applications[id] = application(of: id, before: before)
        }
        let changes = candidates.compactMap { applications[$0]?.change }
        guard !changes.isEmpty else {
            return
        }
        let waiting = try store.apply(SyncLocalChange.ordered(changes))
        let snapshot = try store.snapshot()
        for change in changes {
            let isWaiting = waiting.contains(change.id)
            state.entries[change.id]?.isWaiting = isWaiting
            detectedSnapshot?[change.id] = snapshot[change.id]?.json
            if let application = applications[change.id], !application.keepsBaseline {
                var local = snapshot[change.id]?.json.objectValue
                // The reference keeps the deleted parent: the move to the root is sent as a change of this Mac.
                local?.merge(application.restoredKeys) { _, restored in restored }
                state.entries[change.id]?.local = isWaiting ? nil : local.map(SyncJSON.object)
            }
            if !isWaiting {
                report.received += 1
            }
        }
    }

    /// What applying `id` does; nil if nothing (unreadable, unknown format).
    private func application(of id: UUID, before: [UUID: SyncFields]?) -> Application? {
        guard let entry = state.entries[id], !entry.isUnreadable, let remote = entry.remote else {
            return nil
        }
        let current = before?[id]?.json
        let isChangedHere = before != nil && current != detectedSnapshot?[id]
        if remote.deleted {
            // A modification made here since is newer than this deletion: it recreates the record.
            if isChangedHere, current != nil {
                return Application(keepsBaseline: true)
            }
            return remote.recordType.map { Application(change: .delete(id, $0)) }
        }
        guard var fields = remote.readableFields else {
            // Unknown type, format or value: ignored, without overwriting what this Mac has.
            Logger.sync.notice("Record of an unknown format ignored")
            return nil
        }
        var application = Application()
        if isChangedHere, entry.local != nil {
            application.keepsBaseline = true
            let merged = current.map { SyncFieldMerge.merged(
                remote: remote.fields,
                local: $0,
                baseline: entry.local,
                knownKeys: fields.type.fieldKeys,
            ) }
            // Deleted here since: the deletion leaves next.
            guard let merged = merged.flatMap({ SyncFields(json: $0, type: fields.type) }) else {
                return application
            }
            fields = merged
        }
        switch parentAdjustment(of: fields) {
        case .none:
            break
        case let .reparented(adjusted, keys):
            fields = adjusted
            application.restoredKeys = keys
        case .deleted:
            queueDeletion(of: id, type: fields.type)
            application.change = .delete(id, fields.type)
            return application
        }
        application.change = .upsert(id, fields)
        return application
    }

    /// What was waiting for its parent: tried again when one of its parents was just read (review SY17), never at
    /// every read.
    func retryWaiting(after received: Set<UUID>) throws {
        let waiting = state.entries.compactMap { id, entry -> UUID? in
            guard entry.isWaiting, let parents = entry.remote?.readableFields?.parentIDs else {
                return nil
            }
            return parents.contains(where: received.contains) ? id : nil
        }
        if !waiting.isEmpty {
            try applyRemote(waiting)
        }
    }
}
