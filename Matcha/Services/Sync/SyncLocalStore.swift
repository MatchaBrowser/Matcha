import Foundation

/// This Mac's data as seen by the sync engine: its current state, record by record, and the applying of what is
/// received. Implemented for Matcha by `MatchaSyncStore`, and in memory in tests. A read failure throws: it is never
/// taken for an empty Mac, which would delete everything on all Macs (audit S6).
@MainActor
protocol SyncLocalStore: AnyObject {
    /// Current state of each synced record on this Mac.
    func snapshot() throws -> [UUID: SyncFields]

    /// This Mac's records that don't travel, or not entirely (`SYNC.md` § 2.4 and § 5).
    func exceptions() throws -> SyncLocalExceptions

    /// Applies `changes`, in the given order (parents first); returns the records put on hold because their parent is
    /// missing (`SYNC.md` § 2.3: hidden until it arrives).
    func apply(_ changes: [SyncLocalChange]) throws -> Set<UUID>

    /// True if this Mac only has its first-launch data (`SYNC.md` § 5): at the first sync, it then takes the synced
    /// data and removes its own.
    var hasOnlyFirstLaunchData: Bool { get }

    /// Before a cycle: what must be sent before the records that reference it (extension packages).
    func prepare(using transport: any SyncTransport) async

    /// After a successful cycle: cleanup on the server (old packages).
    func finish(using transport: any SyncTransport) async
}

extension SyncLocalStore {
    func exceptions() throws -> SyncLocalExceptions {
        SyncLocalExceptions()
    }

    func prepare(using _: any SyncTransport) async {}

    func finish(using _: any SyncTransport) async {}
}

/// What doesn't travel among this Mac's records (`SYNC.md` § 2.4 and § 5).
nonisolated struct SyncLocalExceptions: Equatable, Sendable {
    /// Favorites and pinned tabs whose address isn't a web address: absent from the snapshot, not sent, and their
    /// absence isn't a deletion.
    var localRecords: Set<UUID> = []
    /// Today tabs showing a page that isn't a web address: their address and title stay the last ones sent.
    var nonWebPages: Set<UUID> = []
}

/// Received change, to apply on this Mac.
nonisolated enum SyncLocalChange: Equatable, Sendable {
    case upsert(UUID, SyncFields)
    case delete(UUID, SyncRecordType)

    var id: UUID {
        switch self {
        case let .upsert(id, _), let .delete(id, _): id
        }
    }

    /// Application order of a batch: creations and modifications of parents first (profiles, Spaces, folders,
    /// tabs…), then deletions, from the content up to the parents.
    static func ordered(_ changes: [SyncLocalChange]) -> [SyncLocalChange] {
        changes.sorted { first, second in
            switch (first, second) {
            case let (.upsert(_, firstFields), .upsert(_, secondFields)): firstFields.type.applyRank < secondFields.type.applyRank
            case (.upsert, .delete): true
            case (.delete, .upsert): false
            case let (.delete(_, firstType), .delete(_, secondType)): firstType.applyRank > secondType.applyRank
            }
        }
    }
}
