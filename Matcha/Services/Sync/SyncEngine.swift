import Foundation
import OSLog

/// Sync engine (`SYNC.md` § 2 and § 5), the same for all transports. A cycle sends again the batch left without an
/// answer, collects this Mac's changes and sends them, reads the others' and applies them, then sends what is still
/// pending. The state (`SyncState`) is saved after each step: an interrupted cycle resumes where it left off.
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

    /// Answer when the server no longer knows many of this Mac's records (expired cursor, § 5).
    enum RecreationChoice: Sendable {
        /// They are sent again.
        case sendAgain
        /// This Mac takes what the server has.
        case replaceLocal
    }

    /// Summary of a cycle.
    struct Report: Equatable, Sendable {
        var sent = 0
        var received = 0
        var conflicts = 0
    }

    /// From this number of deletions, or of records to create again, more than half of the account asks first (§ 5).
    static let massChangeThreshold = 50

    var state: SyncState
    let store: any SyncLocalStore
    let transport: any SyncTransport
    let identifiers: SyncIdentifiers
    let file: SyncStateFile
    var detector = SyncChangeDetector()
    /// The Mac's time (replaced in tests).
    var now: () -> Date = { .now }
    /// Choice for the first sync when it must be asked; merge by default.
    var chooseFirstSync: @MainActor () async -> FirstSyncChoice = { .merge }
    /// Deletion of `count` records, more than half of the account, about to leave: true to send it. Refused, the
    /// records come back from the synced data.
    var confirmMassDeletion: @MainActor (_ count: Int) async -> Bool = { _ in false }
    /// The server no longer knows `count` records of this Mac, more than half of the account.
    var confirmRecreations: @MainActor (_ count: Int) async -> RecreationChoice = { _ in .sendAgain }
    /// Date at which to read this Mac again for a waiting change of its tabs (`deviceTabs`); nil if there is none.
    var nextCheck: Date?
    private(set) var isSyncing = false
    /// This Mac's clock is more than 24 hours ahead of the server's: nothing is sent until it is corrected, reading goes
    /// on (`SYNC.md` § 2.8).
    var isSendingPaused = false
    var report = Report()
    /// During a full reread: records the server has in an older version than the one accepted here; nil otherwise.
    var staleOnServer: Set<UUID>?

    /// `deviceID`: this Mac's identifier, kept in the keychain; it replaces the one of the state file (a cloned Mac
    /// draws a new one, `SYNC.md` § 5).
    init(
        store: any SyncLocalStore,
        transport: any SyncTransport,
        identifiers: SyncIdentifiers,
        file: SyncStateFile,
        deviceID: UUID? = nil,
    ) {
        self.store = store
        self.transport = transport
        self.identifiers = identifiers
        self.file = file
        switch file.load() {
        case let .state(loaded):
            state = loaded
        case .missing:
            state = SyncState()
        case .unreadable:
            Logger.sync.error("Unreadable sync state set aside: merging with the synced data")
            state = SyncState()
            state.mergesWithoutAsking = true
        }
        if let deviceID {
            state.deviceID = deviceID
        }
        // Today tabs no longer travel (`SYNC.md` § 2.4): those of an older version are forgotten, never deleted.
        state.forgetTodayTabs()
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
        try await resendInFlight()
        if state.hasCompletedFirstSync {
            try detectLocalChanges()
            try await guardMassDeletion()
            try await push()
            try await pull()
            // Received deletions can move or delete content here (a folder's tabs back to the root…): sent too.
            try detectLocalChanges()
            try await guardMassDeletion()
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
    func detectLocalChanges() throws {
        let snapshot = try store.snapshot()
        let exceptions = try store.exceptions()
        let (changes, next) = detector.changes(in: snapshot, exceptions: exceptions, state: state, now: now())
        nextCheck = next
        changes.forEach(record)
    }

    /// Queues `change`: the content replaced (pending or accepted) with this Mac's changed fields, dated after it.
    private func record(_ change: SyncChangeDetector.Change) {
        let id = change.id
        state.rejected[id] = nil
        let entry = state.entries[id]
        let replaced = state.pending[id]?.content ?? entry?.remote
        if let fields = change.fields {
            let local = fields.json
            var content = SyncContent(
                fields: fields,
                modifiedAt: state.clock.next(now: now(), after: replaced?.modifiedAt),
                modifiedBy: state.deviceID,
            )
            if let replaced, !replaced.deleted, replaced.type == content.type {
                content.fields = SyncFieldMerge.merged(remote: replaced.fields, local: local, baseline: state.baseline(of: id))
            }
            state.pending[id] = SyncPendingChange(content: content, local: local)
        } else if entry?.version == nil {
            // Never reached the server: nothing to delete there.
            state.pending[id] = nil
            state.entries[id] = nil
        } else if entry?.remote?.deleted == true, state.pending[id] == nil {
            // Deleted on the server already (received deletion, cascade): nothing to send.
            state.entries[id]?.local = nil
        } else if let type = state.type(of: id) {
            let schema = SyncRecordType(rawValue: type)?.schema ?? 1
            let deletion = SyncContent.deletion(
                of: type,
                schema: schema,
                modifiedAt: state.clock.next(now: now(), after: replaced?.modifiedAt),
                modifiedBy: state.deviceID,
            )
            state.pending[id] = SyncPendingChange(content: deletion, local: nil)
        }
    }

    /// Deletion of a record this Mac doesn't have, sent at the next cycle: the tabs of a Mac the user revoked (`SYNC.md`
    /// § 2.4). Nothing if the server has no content for it.
    func queueDeletion(of id: UUID, type: SyncRecordType) {
        guard let entry = state.entries[id], entry.version != nil, entry.remote?.deleted == false else {
            return
        }
        let deletion = SyncContent.deletion(
            of: type.rawValue,
            schema: type.schema,
            modifiedAt: state.clock.next(now: now(), after: entry.remote?.modifiedAt),
            modifiedBy: state.deviceID,
        )
        state.pending[id] = SyncPendingChange(content: deletion, local: nil)
    }

    /// Deletion of more than half of the account's records (and at least 50) about to leave: asks first. Refused, the
    /// records come back on this Mac from the synced data (`SYNC.md` § 5).
    func guardMassDeletion() async throws {
        let deletions = state.pending.compactMap { id, change in
            change.content.deleted && state.entries[id]?.version != nil ? id : nil
        }
        guard deletions.count >= Self.massChangeThreshold, deletions.count * 2 > state.liveRecordCount else {
            return
        }
        if await confirmMassDeletion(deletions.count) {
            return
        }
        Logger.sync.notice("Mass deletion refused: \(deletions.count, privacy: .public) records restored")
        for id in deletions {
            state.pending[id] = nil
        }
        try applyRemote(deletions)
        save()
    }

    // MARK: Reception

    /// Content of `record` if it can be trusted: readable, and whose identifier is the one its fields give (a
    /// deletion has no fields: the encryption already binds it to its identifier, `SYNC.md` § 2.2).
    func verified(_ record: SyncRemoteRecord) -> SyncContent? {
        guard let content = record.content else {
            return nil
        }
        let expected = content.deleted ? nil : content.readableFields.flatMap(identifiers.expectedID(of:))
        if let expected, expected != record.id {
            Logger.sync.error("Record whose identifier doesn't match its fields: ignored")
            return nil
        }
        return content
    }

    /// Takes a received date into account for the clock; a date too far in the future is noted, without moving it.
    func observe(_ content: SyncContent) {
        if !state.clock.observe(content.modifiedAt, now: now()) {
            Logger.sync.notice("Received date far in the future: clock unchanged")
            state.sawFutureDate = true
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
