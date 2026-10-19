import Foundation
@testable import Matcha

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
    /// Rejected changes (`payload_too_large`).
    var refused: Set<UUID> = []

    func setPageSize(_ size: Int) {
        pageSize = size
    }

    func refuse(_ id: UUID) {
        refused.insert(id)
    }

    func unrefuse(_ id: UUID) {
        refused.remove(id)
    }

    func push(_ changes: [SyncOutgoingChange]) -> [SyncPushResult] {
        changes.map { change in
            if refused.contains(change.id) {
                return .rejected(code: "payload_too_large")
            }
            if let current = records[change.id], current.version != change.baseVersion {
                return .conflict(current: current)
            }
            return .applied(version: write(change.id, change.content))
        }
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

    func push(_ changes: [SyncOutgoingChange]) async throws -> [SyncPushResult] {
        await server.push(changes)
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

/// A Mac's data in memory: a record waits as long as one of its parents is missing.
@MainActor
final class MemorySyncStore: SyncLocalStore {
    var items: [UUID: SyncFields] = [:]
    var hasOnlyFirstLaunchData = false
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

    init(server: InMemorySyncServer, time: Date = Date(timeIntervalSince1970: 1_800_000_000), maxChangesPerPush: Int = 500) {
        engine = SyncEngine(
            store: store,
            transport: InMemorySyncTransport(server: server, maxChangesPerPush: maxChangesPerPush),
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

    func addProfile(_ name: String, order: Int = 0) -> UUID {
        let id = UUID()
        store.items[id] = .profile(SyncProfileFields(name: name, order: order))
        return id
    }

    func addSpace(_ name: String, profile: UUID, order: Int = 0) -> UUID {
        let id = UUID()
        store.items[id] = .space(SyncSpaceFields(name: name, symbol: "circle.fill", theme: nil, order: order, profileId: profile))
        return id
    }

    @discardableResult
    func addTodayTab(in space: UUID, url: String? = nil, order: Int = 0) -> UUID {
        let id = UUID()
        store.items[id] = .tab(todayTab(in: space, url: url, order: order))
        return id
    }

    func todayTab(in space: UUID, url: String?, order: Int = 0) -> SyncTabFields {
        SyncTabFields(
            place: .today,
            url: url.flatMap(URL.init(string:)),
            title: url,
            order: order,
            profileId: nil,
            spaceId: space,
            folderId: nil,
            lastActivity: nil,
        )
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
