import Foundation

/// Sync transport (task 7.4): what differs between a server (7.7) and iCloud (postponed). It sends batches, reads
/// changes since a cursor, and encrypts or decrypts contents (`SYNC.md` § 3.5): the engine only sees plaintext
/// contents.
protocol SyncTransport: Sendable {
    /// Number of changes per push (`maxChangesPerPush`).
    var maxChangesPerPush: Int { get }

    /// Sends `changes`, in order; one result per change, in the same order.
    func push(_ changes: [SyncOutgoingChange]) async throws -> [SyncPushResult]

    /// Changes written after `cursor` (nil: from the beginning), by increasing version. Throws
    /// `SyncTransportError.cursorExpired` if the cursor is too old.
    func changes(since cursor: String?) async throws -> SyncChangePage

    /// True if the transport stores extension packages (`SYNC.md` § 4.7); otherwise, an extension installed from a
    /// file travels without its package.
    var supportsBlobs: Bool { get }

    /// Uploads an already encrypted package; no effect if the same one already exists under this identifier.
    func putBlob(_ data: Data, id: UUID) async throws

    /// Encrypted package `id`; throws `SyncTransportError.blobNotFound` if it is not there (yet).
    func blob(id: UUID) async throws -> Data

    /// Deletes the package `id` (no error if it does not exist).
    func deleteBlob(id: UUID) async throws
}

/// Sent change: `baseVersion` is the version it is based on, nil for a creation.
nonisolated struct SyncOutgoingChange: Equatable, Sendable {
    let id: UUID
    let baseVersion: Int?
    let content: SyncContent
}

/// Record read from the server. `content` is nil if it could not be decrypted or read: it is then ignored, and never
/// overwritten.
nonisolated struct SyncRemoteRecord: Equatable, Sendable {
    let id: UUID
    let version: Int
    let content: SyncContent?
}

/// Outcome of a sent change (`SYNC.md` § 4.6).
nonisolated enum SyncPushResult: Equatable, Sendable {
    case applied(version: Int)
    /// `baseVersion` was no longer the server's version: nothing is written, here is the current record.
    case conflict(current: SyncRemoteRecord)
    case rejected(code: String)
}

/// A page of changes read.
nonisolated struct SyncChangePage: Equatable, Sendable {
    let records: [SyncRemoteRecord]
    let cursor: String
    let hasMore: Bool
}

nonisolated enum SyncTransportError: Error, Equatable {
    /// Cursor too old (`410 cursor_expired`): read everything again from the beginning.
    case cursorExpired
    /// Missing package (`404`): it may arrive later.
    case blobNotFound
    /// Another package already has this identifier (`409 blob_exists`).
    case blobExists
}
