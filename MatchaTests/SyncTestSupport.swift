import Foundation
@testable import Matcha

/// Serveur de synchro en mémoire, avec les règles de l'API (`SYNC.md` § 4.6) : un compteur par compte, un changement
/// appliqué seulement sur la version actuelle, pages par version croissante, curseur expiré après une purge. Les
/// contenus restent en clair (le chiffrement est celui du transport d'un serveur).
actor InMemorySyncServer {
    private(set) var counter = 0
    private(set) var records: [UUID: SyncRemoteRecord] = [:]
    /// Taille des pages lues.
    var pageSize = 500
    /// Curseurs plus anciens que cette version : expirés.
    private var oldestCursor = 0
    /// Changements refusés (`payload_too_large`).
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

    /// Écrit `content` comme un autre client (version plus récente de Matcha, contenu illisible…).
    @discardableResult
    func write(_ id: UUID, _ content: SyncContent?) -> Int {
        counter += 1
        records[id] = SyncRemoteRecord(id: id, version: counter, content: content)
        return counter
    }

    /// Oublie les suppressions, comme après 180 jours : les curseurs d'avant expirent.
    func purgeDeletions() {
        records = records.filter { $0.value.content?.deleted != true }
        oldestCursor = counter
    }

    /// Contenu actuel de `id`.
    func content(of id: UUID) -> SyncContent? {
        records[id]?.content
    }
}

/// Transport vers un `InMemorySyncServer`.
struct InMemorySyncTransport: SyncTransport {
    let server: InMemorySyncServer
    var maxChangesPerPush = 500

    func push(_ changes: [SyncOutgoingChange]) async throws -> [SyncPushResult] {
        await server.push(changes)
    }

    func changes(since cursor: String?) async throws -> SyncChangePage {
        try await server.changes(since: cursor)
    }
}

/// Données d'un Mac en mémoire : un enregistrement attend tant qu'un de ses parents manque.
@MainActor
final class MemorySyncStore: SyncLocalStore {
    var items: [UUID: SyncFields] = [:]
    var hasOnlyFirstLaunchData = false
    /// Changements appliqués, dans l'ordre.
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

/// Un Mac simulé : ses données, son moteur, son heure.
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

    // MARK: Données

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
