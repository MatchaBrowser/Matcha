import CryptoKit
import Foundation
@testable import Matcha

extension SyncIdentifiers {
    /// Identifiers of the test account: the same for all the simulated Macs.
    static let testAccount = SyncIdentifiers(idKey: SymmetricKey(data: Data(repeating: 7, count: 32)))
}

/// In-memory sync server, with the API rules (`SYNC.md` § 4.6): one counter per account, a change applied only on the
/// current version, pages by increasing version, cursor expired after a purge. The contents stay in clear text (the
/// encryption is that of a server's transport).
actor InMemorySyncServer {
    private(set) var counter = 0
    private(set) var records: [UUID: SyncRemoteRecord] = [:]
    /// Size of the pages read.
    var pageSize = 500
    /// Cursors older than this version: expired.
    private var oldestCursor = 0
    /// Rejected changes, with their code (`payload_too_large` by default).
    var refused: [UUID: String] = [:]
    /// Answers already given, by `Idempotency-Key`: a batch sent again gets the same answer, without being written.
    private var answers: [UUID: [SyncPushResult]] = [:]
    /// Number of batches actually written.
    private(set) var writtenBatches = 0

    func setPageSize(_ size: Int) {
        pageSize = size
    }

    func refuse(_ id: UUID, code: String = SyncRejectionCode.payloadTooLarge) {
        refused[id] = code
    }

    func unrefuse(_ id: UUID) {
        refused[id] = nil
    }

    func push(_ batch: SyncPreparedBatch) -> [SyncPushResult] {
        if let answer = answers[batch.key] {
            return answer
        }
        writtenBatches += 1
        let answer = batch.changes.map { change -> SyncPushResult in
            if let code = refused[change.id] {
                return .rejected(code: code)
            }
            guard let current = records[change.id] else {
                // Unknown identifier: a creation, or a conflict with nothing if the change was based on a version.
                return change.baseVersion == nil ? .applied(version: write(change.id, change.content)) : .conflict(current: nil)
            }
            if current.version != change.baseVersion {
                return .conflict(current: current)
            }
            return .applied(version: write(change.id, change.content))
        }
        answers[batch.key] = answer
        return answer
    }

    /// Forgets `id` entirely, as after a purge or a restored backup.
    func forget(_ id: UUID) {
        records[id] = nil
    }

    func changes(since cursor: String?) throws -> SyncChangePage {
        let after = cursor.flatMap { Int($0.dropFirst(2)) } ?? 0
        if cursor != nil, after < oldestCursor {
            throw SyncTransportError.cursorExpired
        }
        let newer = records.values.filter { $0.version > after }.sorted { $0.version < $1.version }
        let page = Array(newer.prefix(pageSize))
        let last = page.last?.version ?? max(after, counter)
        return SyncChangePage(records: page, cursor: "c_\(last)", hasMore: newer.count > page.count)
    }

    /// Writes `content` as another client would (newer version of Matcha, unreadable content…).
    @discardableResult
    func write(_ id: UUID, _ content: SyncContent?) -> Int {
        counter += 1
        records[id] = SyncRemoteRecord(id: id, version: counter, content: content)
        return counter
    }

    /// Puts back `backup` (an earlier copy of `records`), as a restored server: earlier cursors expire (review SY10).
    func restore(_ backup: [UUID: SyncRemoteRecord]) {
        records = backup
        oldestCursor = counter + 1
    }

    /// Forgets deletions, as after 180 days: earlier cursors expire.
    func purgeDeletions() {
        records = records.filter { $0.value.content?.deleted != true }
        oldestCursor = counter
    }

    /// Current content of `id`.
    func content(of id: UUID) -> SyncContent? {
        records[id]?.content
    }

    // MARK: Blobs

    private(set) var blobs: [UUID: Data] = [:]

    func putBlob(_ data: Data, id: UUID) throws {
        if let existing = blobs[id], existing != data {
            throw SyncTransportError.blobExists
        }
        blobs[id] = data
    }

    func blob(id: UUID) throws -> Data {
        guard let data = blobs[id] else {
            throw SyncTransportError.blobNotFound
        }
        return data
    }

    func deleteBlob(id: UUID) {
        blobs[id] = nil
    }

    /// Replaces blob `id` without checks (blob tampered with by the server).
    func replaceBlob(_ data: Data, id: UUID) {
        blobs[id] = data
    }
}

/// Transport to an `InMemorySyncServer`.
struct InMemorySyncTransport: SyncTransport {
    let server: InMemorySyncServer
    var maxChangesPerPush = 500

    func push(_ batch: SyncPreparedBatch) async throws -> [SyncPushResult] {
        await server.push(batch)
    }

    func changes(since cursor: String?) async throws -> SyncChangePage {
        try await server.changes(since: cursor)
    }

    var supportsBlobs: Bool {
        true
    }

    func putBlob(_ data: Data, id: UUID) async throws {
        try await server.putBlob(data, id: id)
    }

    func blob(id: UUID) async throws -> Data {
        try await server.blob(id: id)
    }

    func deleteBlob(id: UUID) async throws {
        await server.deleteBlob(id: id)
    }
}

/// Transport whose next pushes reach the server but lose their answer (network cut after sending).
struct LossyTransport: SyncTransport {
    actor Losses {
        var remaining: Int

        init(_ count: Int) {
            remaining = count
        }

        func take() -> Bool {
            guard remaining > 0 else {
                return false
            }
            remaining -= 1
            return true
        }
    }

    let server: InMemorySyncServer
    let losses: Losses
    var maxChangesPerPush = 500

    func push(_ batch: SyncPreparedBatch) async throws -> [SyncPushResult] {
        let answer = await server.push(batch)
        if await losses.take() {
            throw URLError(.networkConnectionLost)
        }
        return answer
    }

    func changes(since cursor: String?) async throws -> SyncChangePage {
        try await server.changes(since: cursor)
    }

    var supportsBlobs: Bool {
        false
    }

    func putBlob(_: Data, id _: UUID) async throws {}

    func blob(id _: UUID) async throws -> Data {
        throw SyncTransportError.blobNotFound
    }

    func deleteBlob(id _: UUID) async throws {}
}

/// Transport that refuses to prepare a batch of more than one change, as a server whose request limit is tiny.
struct TinyRequestTransport: SyncTransport {
    let server: InMemorySyncServer
    var maxChangesPerPush = 500

    func prepare(_ changes: [SyncOutgoingChange]) throws -> SyncPreparedBatch {
        guard changes.count <= 1 else {
            throw SyncTransportError.batchTooLarge
        }
        return SyncPreparedBatch(key: UUID(), changes: changes, body: Data())
    }

    func push(_ batch: SyncPreparedBatch) async throws -> [SyncPushResult] {
        await server.push(batch)
    }

    func changes(since cursor: String?) async throws -> SyncChangePage {
        try await server.changes(since: cursor)
    }

    var supportsBlobs: Bool {
        false
    }

    func putBlob(_: Data, id _: UUID) async throws {}

    func blob(id _: UUID) async throws -> Data {
        throw SyncTransportError.blobNotFound
    }

    func deleteBlob(id _: UUID) async throws {}
}

/// A Mac's data in memory: a record waits as long as one of its parents is missing.
@MainActor
final class MemorySyncStore: SyncLocalStore {
    var items: [UUID: SyncFields] = [:]
    var hasOnlyFirstLaunchData = false
    /// Records just taken from the synced data (an extension installed from an offer).
    var adopted: Set<UUID> = []

    func takeAdoptedRecords() -> Set<UUID> {
        defer { adopted = [] }
        return adopted
    }

    /// Changes applied, in order.
    private(set) var applied: [SyncLocalChange] = []

    func snapshot() -> [UUID: SyncFields] {
        items
    }

    func apply(_ changes: [SyncLocalChange]) -> Set<UUID> {
        var waiting: Set<UUID> = []
        for change in changes {
            applied.append(change)
            switch change {
            case .upsert(_, .deviceTabs):
                // Like `MatchaSyncStore`: the other Macs' tabs are only shown, never applied.
                continue
            case let .upsert(id, fields):
                if fields.parentIDs.contains(where: { items[$0] == nil }) {
                    waiting.insert(id)
                } else {
                    items[id] = fields
                }
            case let .delete(id, _):
                items[id] = nil
            }
        }
        return waiting
    }
}

/// A simulated Mac: its data, its engine, its clock.
@MainActor
final class SimulatedMac {
    let store = MemorySyncStore()
    let engine: SyncEngine
    var time: Date

    init(
        server: InMemorySyncServer,
        time: Date = Date(timeIntervalSince1970: 1_800_000_000),
        maxChangesPerPush: Int = 500,
        transport: (any SyncTransport)? = nil,
    ) {
        engine = SyncEngine(
            store: store,
            transport: transport ?? InMemorySyncTransport(server: server, maxChangesPerPush: maxChangesPerPush),
            identifiers: .testAccount,
            file: SyncStateFile(url: nil),
        )
        self.time = time
        engine.now = { [unowned self] in self.time }
    }

    @discardableResult
    func sync(after seconds: TimeInterval = 1) async throws -> SyncEngine.Report? {
        time += seconds
        return try await engine.sync()
    }

    // MARK: Data

    func addProfile(_ name: String, order: Double = 0) -> UUID {
        let id = UUID()
        store.items[id] = .profile(SyncProfileFields(name: name, order: order))
        return id
    }

    func addSpace(_ name: String, profile: UUID, order: Double = 0) -> UUID {
        let id = UUID()
        store.items[id] = .space(SyncSpaceFields(name: name, symbol: "circle.fill", theme: nil, order: order, profileId: profile))
        return id
    }

    @discardableResult
    func addPinnedTab(in space: UUID, url: String? = nil, order: Double = 0) -> UUID {
        let id = UUID()
        store.items[id] = .tab(pinnedTab(in: space, url: url, order: order))
        return id
    }

    func pinnedTab(in space: UUID, url: String?, order: Double = 0) -> SyncTabFields {
        SyncTabFields(place: .pinned, url: url.flatMap(URL.init(string:)), title: url, order: order, spaceId: space)
    }

    func rename(_ id: UUID, to name: String) {
        switch store.items[id] {
        case var .profile(fields):
            fields.name = name
            store.items[id] = .profile(fields)
        case var .space(fields):
            fields.name = name
            store.items[id] = .space(fields)
        default:
            break
        }
    }

    func name(of id: UUID) -> String? {
        switch store.items[id] {
        case let .profile(fields): fields.name
        case let .space(fields): fields.name
        default: nil
        }
    }

    func url(of id: UUID) -> URL? {
        if case let .tab(fields) = store.items[id] {
            return fields.url
        }
        return nil
    }
}
