import Foundation
import OSLog

/// Sync engine (task 7.4, `SYNC.md` § 2 and § 5), the same for all transports. A cycle collects this Mac's changes,
/// sends them, reads the others' and applies them, then sends what is still pending. The state (`SyncState`)
/// is saved after each step: an interrupted cycle resumes where it left off.
@MainActor
final class SyncEngine {
    /// Choice for the first sync when this Mac and the synced data each have their own data (§ 5).
    enum FirstSyncChoice: Sendable {
        /// Union by identifier; what is already synced wins.
        case merge
        /// This Mac takes the synced data and removes its own.
        case replaceLocal
        /// This Mac's data replaces the synced data.
        case replaceRemote
    }

    /// Summary of a cycle.
    struct Report: Equatable, Sendable {
        var sent = 0
        var received = 0
        var conflicts = 0
    }

    var state: SyncState
    let store: any SyncLocalStore
    let transport: any SyncTransport
    private let file: SyncStateFile
    var detector = SyncChangeDetector()
    /// The Mac's time (replaced in tests).
    var now: () -> Date = { .now }
    /// Choice for the first sync when it must be asked; merge by default.
    var chooseFirstSync: @MainActor () async -> FirstSyncChoice = { .merge }
    /// Date at which to read this Mac again for a waiting today tab page; nil if there is none.
    private(set) var nextCheck: Date?
    private(set) var isSyncing = false
    var report = Report()

    init(store: any SyncLocalStore, transport: any SyncTransport, file: SyncStateFile) {
        self.store = store
        self.transport = transport
        self.file = file
        state = file.load() ?? SyncState()
    }

    /// One cycle; nil if a cycle is already running (only one sync at a time).
    @discardableResult
    func sync() async throws -> Report? {
        guard !isSyncing else {
            return nil
        }
        isSyncing = true
        report = Report()
        defer { isSyncing = false }
        await store.prepare(using: transport)
        if state.hasCompletedFirstSync {
            detectLocalChanges()
            try await push()
            try await pull()
        } else {
            try await firstSync()
        }
        // This Mac's changes that are newer than those read: sent again on top of the version read.
        try await push()
        save()
        await store.finish(using: transport)
        let (sent, received, conflicts) = (report.sent, report.received, report.conflicts)
        Logger.sync.info(
            "Sync: \(sent, privacy: .public) sent, \(received, privacy: .public) received, \(conflicts, privacy: .public) conflicts",
        )
        return report
    }

    // MARK: This Mac's changes

    /// Collects this Mac's changes since its last sync and queues them for sending.
    func detectLocalChanges() {
        let (changes, next) = detector.changes(in: store.snapshot(), state: state, now: now())
        nextCheck = next
        changes.forEach(record)
    }

    private func record(_ change: SyncChangeDetector.Change) {
        let id = change.id
        state.rejected[id] = nil
        if let fields = change.fields {
            var content = SyncContent(fields: fields, modifiedAt: state.clock.next(now: now()), modifiedBy: state.deviceID)
            if let remote = state.entries[id]?.remote, !remote.deleted, remote.type == content.type {
                content.fields = content.fields.keepingUnknownKeys(of: remote.fields)
            }
            state.pending[id] = SyncPendingChange(content: content, local: fields.json)
        } else if state.entries[id]?.version == nil {
            // Never reached the server: nothing to delete there.
            state.pending[id] = nil
            state.entries[id] = nil
        } else if let type = state.type(of: id) {
            let schema = SyncRecordType(rawValue: type)?.schema ?? 1
            let deletion = SyncContent.deletion(
                of: type,
                schema: schema,
                modifiedAt: state.clock.next(now: now()),
                modifiedBy: state.deviceID,
            )
            state.pending[id] = SyncPendingChange(content: deletion, local: nil)
        }
    }

    func save() {
        do {
            try file.save(state)
        } catch {
            Logger.sync.error("Sync state not saved: \(error.logSummary, privacy: .public)")
        }
    }
}
