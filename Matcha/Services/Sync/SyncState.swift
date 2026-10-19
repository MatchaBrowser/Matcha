import Foundation

/// This Mac's sync state (task 7.4), kept from one launch to the next: device identifier, read cursor, clock, what
/// the server has of each record and what this Mac had of it then, changes waiting to be sent. Pure type.
nonisolated struct SyncState: Codable, Equatable, Sendable {
    var deviceID = UUID()
    var cursor: String?
    var clock = SyncClock()
    var entries: [UUID: SyncEntry] = [:]
    var pending: [UUID: SyncPendingChange] = [:]
    /// Fields rejected by the server (too big…): not sent again as long as they do not change.
    var rejected: [UUID: SyncJSON] = [:]
    var hasCompletedFirstSync = false

    /// What this Mac had of `id` at its last sync, or what it is about to send; nil: nothing (absent).
    func baseline(of id: UUID) -> SyncJSON? {
        if let pending = pending[id] {
            return pending.local
        }
        return entries[id]?.local
    }

    /// Known type of `id`.
    func type(of id: UUID) -> String? {
        pending[id]?.content.type ?? entries[id]?.type
    }
}

/// A record known to sync.
nonisolated struct SyncEntry: Codable, Equatable, Sendable {
    var type: String
    /// Version on the server; nil if it is not there yet.
    var version: Int?
    /// Last known content from the server.
    var remote: SyncContent?
    /// This Mac's fields at the record's last sync; nil if it was not on this Mac.
    var local: SyncJSON?
    /// Received but not applied yet: its parent is missing.
    var isWaiting = false
}

/// Change on this Mac waiting to be sent: the content, and the fields of this Mac it carries (nil: deletion).
nonisolated struct SyncPendingChange: Codable, Equatable, Sendable {
    var content: SyncContent
    var local: SyncJSON?
}

/// File of the sync state (JSON); without a URL (tests), nothing is written.
nonisolated struct SyncStateFile: Sendable {
    let url: URL?

    func load() -> SyncState? {
        guard let url, let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? SyncCoding.decoder().decode(SyncState.self, from: data)
    }

    func save(_ state: SyncState) throws {
        guard let url else {
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SyncCoding.encoder().encode(state).write(to: url, options: .atomic)
    }
}
