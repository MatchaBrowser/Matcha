import Foundation

/// This Mac's sync state for one account (`SYNC.md` § 5), kept from one launch to the next: device identifier, read
/// cursor, clock, what the server has of each record and what this Mac had of it then, changes waiting to be sent, and
/// the batch sent without an answer yet. Decoded leniently: a field missing from an older file takes its default
/// value. Pure type.
nonisolated struct SyncState: Codable, Equatable, Sendable {
    var deviceID = UUID()
    var cursor: String?
    var clock = SyncClock()
    var entries: [UUID: SyncEntry] = [:]
    var pending: [UUID: SyncPendingChange] = [:]
    /// Changes refused by the server (too big…): not sent again as long as this Mac's fields don't change.
    var rejected: [UUID: SyncRejection] = [:]
    var hasCompletedFirstSync = false
    /// Batch sent without an answer (network error, quit): sent again first, exactly as it was, with its key.
    var inFlight: SyncInFlight?
    /// The state file was unreadable and set aside: the first sync merges without asking (`SYNC.md` § 5).
    var mergesWithoutAsking = false
    /// The account's space is full: deletions are sent first, in a batch of their own (`SYNC.md` § 4.6).
    var isQuotaExceeded = false
    /// A received date was too far in the future to be taken into account by the clock (`SYNC.md` § 2.8).
    var sawFutureDate = false

    init(deviceID: UUID = UUID()) {
        self.deviceID = deviceID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decode(UUID.self, forKey: .deviceID)
        cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
        clock = try container.decodeIfPresent(SyncClock.self, forKey: .clock) ?? SyncClock()
        entries = try container.decodeIfPresent([UUID: SyncEntry].self, forKey: .entries) ?? [:]
        pending = try container.decodeIfPresent([UUID: SyncPendingChange].self, forKey: .pending) ?? [:]
        rejected = try container.decodeIfPresent([UUID: SyncRejection].self, forKey: .rejected) ?? [:]
        hasCompletedFirstSync = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedFirstSync) ?? false
        inFlight = try container.decodeIfPresent(SyncInFlight.self, forKey: .inFlight)
        mergesWithoutAsking = try container.decodeIfPresent(Bool.self, forKey: .mergesWithoutAsking) ?? false
        isQuotaExceeded = try container.decodeIfPresent(Bool.self, forKey: .isQuotaExceeded) ?? false
        sawFutureDate = try container.decodeIfPresent(Bool.self, forKey: .sawFutureDate) ?? false
    }

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

    /// Records of the account that exist on the server, as far as this Mac knows.
    var liveRecordCount: Int {
        entries.values.count { $0.version != nil && $0.remote?.deleted == false }
    }
}

/// A record known to sync.
nonisolated struct SyncEntry: Codable, Equatable, Sendable {
    var type: String
    /// Version on the server; nil if it is not there yet.
    var version: Int?
    /// Last content accepted from the server or sent by this Mac: a received content that isn't newer is ignored
    /// (`SYNC.md` § 2.3, no going back).
    var remote: SyncContent?
    /// This Mac's fields at the record's last sync; nil if it was not on this Mac.
    var local: SyncJSON?
    /// Received but not applied yet: its parent is missing.
    var isWaiting = false
    /// Last content received unreadable (decryption, format, derived identifier): never applied nor overwritten.
    var isUnreadable = false

    init(type: String, version: Int? = nil, remote: SyncContent? = nil, local: SyncJSON? = nil) {
        self.type = type
        self.version = version
        self.remote = remote
        self.local = local
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
        remote = try container.decodeIfPresent(SyncContent.self, forKey: .remote)
        local = try container.decodeIfPresent(SyncJSON.self, forKey: .local)
        isWaiting = try container.decodeIfPresent(Bool.self, forKey: .isWaiting) ?? false
        isUnreadable = try container.decodeIfPresent(Bool.self, forKey: .isUnreadable) ?? false
    }

    /// Kept as it is, never modified here: unreadable, or from a newer version of Matcha (unknown type or `schema`).
    var isIgnored: Bool {
        isUnreadable || remote?.isFromNewerVersion == true
    }
}

/// Change on this Mac waiting to be sent: the content, and the fields of this Mac it carries (nil: deletion).
nonisolated struct SyncPendingChange: Codable, Equatable, Sendable {
    var content: SyncContent
    var local: SyncJSON?
}

/// Change refused by the server, with its code (`payload_too_large`, `invalid_payload`) and the fields of this Mac
/// it carried: it leaves again only when they change.
nonisolated struct SyncRejection: Codable, Equatable, Sendable {
    var code: String
    var local: SyncJSON
}

/// Batch sent and not answered yet, with the changes as they were when it left: a change made since then leaves in
/// the next batch.
nonisolated struct SyncInFlight: Codable, Equatable, Sendable {
    var batch: SyncPreparedBatch
    var sent: [UUID: SyncPendingChange]
}

/// File of the sync state (JSON); without a URL (tests), nothing is written. An unreadable file is set aside, renamed,
/// rather than overwritten (`SYNC.md` § 5).
nonisolated struct SyncStateFile: Sendable {
    let url: URL?

    enum Loaded: Equatable {
        case state(SyncState)
        case missing
        /// Set aside: the sync starts over with the same account, merging without asking.
        case unreadable
    }

    func load() -> Loaded {
        guard let url, let data = try? Data(contentsOf: url) else {
            return .missing
        }
        do {
            return try .state(SyncCoding.decoder().decode(SyncState.self, from: data))
        } catch {
            let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date.now.timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return .unreadable
        }
    }

    func save(_ state: SyncState) throws {
        guard let url else {
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SyncCoding.encoder().encode(state).write(to: url, options: .atomic)
    }

    /// Deletes the file (sign-out, deleted account): it copies part of the data in clear text.
    func delete() {
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
