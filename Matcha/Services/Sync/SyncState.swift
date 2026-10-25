import Foundation
import OSLog

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
    /// Last time a received date was too far in the future to be taken into account by the clock (`SYNC.md` § 2.8);
    /// the warning goes away a week later (review SY27).
    var futureDateSeenAt: Date?
    /// Received contents accepted but not applied on this Mac yet (a later batch failed, applying threw): applied at
    /// the next step, never forgotten (review SY6).
    var toApply: Set<UUID> = []

    /// How long the warning about a date in the future stays.
    static let futureDateWarningLifetime: TimeInterval = 7 * 24 * 60 * 60
    /// Deletions and records waiting for their parent are forgotten after this long: the server keeps a deletion 180
    /// days, and an older cursor reads everything again (`SYNC.md` § 4.6, review SY14).
    static let tombstoneLifetime: TimeInterval = 180 * 24 * 60 * 60

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
        futureDateSeenAt = try container.decodeIfPresent(Date.self, forKey: .futureDateSeenAt)
        toApply = try container.decodeIfPresent(Set<UUID>.self, forKey: .toApply) ?? []
    }

    /// True if one of the account's Macs seems to be ahead: a date in the future was received this week.
    func showsFutureDateWarning(now: Date = .now) -> Bool {
        futureDateSeenAt.map { now.timeIntervalSince($0) < Self.futureDateWarningLifetime } ?? false
    }

    /// Forgets the deletions, and the records waiting for a parent, older than `tombstoneLifetime` (review SY14); a
    /// pending change keeps its entry.
    mutating func purgeOldEntries(now: Date = .now) {
        let limit = now.addingTimeInterval(-Self.tombstoneLifetime)
        for (id, entry) in entries where pending[id] == nil && !toApply.contains(id) {
            guard let remote = entry.remote, remote.modifiedAt < limit, remote.deleted || entry.isWaiting else {
                continue
            }
            entries[id] = nil
        }
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

    /// A missing file is a first sync; a file that can't be read or decoded is unreadable, never taken for a missing
    /// one (review TR4).
    func load() -> Loaded {
        guard let url else {
            return .missing
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return .missing
        } catch {
            Logger.sync.error("Sync state unreadable: \(error.logSummary, privacy: .public)")
            return .unreadable
        }
        do {
            return try .state(SyncCoding.decoder().decode(SyncState.self, from: data))
        } catch {
            let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date.now.timeIntervalSince1970)).json")
            do {
                try FileManager.default.moveItem(at: url, to: aside)
            } catch {
                Logger.sync.error("Unreadable sync state not set aside: \(error.logSummary, privacy: .public)")
            }
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
