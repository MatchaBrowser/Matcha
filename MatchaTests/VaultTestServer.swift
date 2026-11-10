import CryptoKit
import Foundation
@testable import Matcha

/// A sync server in memory for the vault's tests: it applies pushes as the reference server does (`SYNC.md` § 4.6,
/// atomic pushes included), and gives each Mac the sync state a complete read would leave it. It can also misbehave:
/// hide records, show an older state, or take a write made with the data key only.
@MainActor
final class VaultTestServer {
    struct Record {
        var version: Int
        var deleted: Bool
        var payload: String
    }

    private(set) var records: [UUID: Record] = [:]
    private var counter = 0
    let dataKey: SymmetricKey

    init(dataKey: SymmetricKey) {
        self.dataKey = dataKey
    }

    func push(_ body: Data, key _: UUID) throws -> SyncPushResponse {
        let request = try SyncCoding.decoder().decode(SyncPushRequest.self, from: body)
        if request.atomic == true {
            return pushAtomic(request.changes)
        }
        return SyncPushResponse(results: request.changes.map { apply($0) })
    }

    private func pushAtomic(_ changes: [SyncServerChange]) -> SyncPushResponse {
        let conflicts = changes.map(conflict)
        guard conflicts.allSatisfy({ $0 == nil }) else {
            let results = zip(changes, conflicts).map { change, conflict in
                conflict ?? SyncServerPushResult(id: change.id, status: "aborted")
            }
            return SyncPushResponse(results: results)
        }
        return SyncPushResponse(results: changes.map { apply($0) })
    }

    /// The conflict a change would be in, or nil if it would be applied.
    private func conflict(_ change: SyncServerChange) -> SyncServerPushResult? {
        let current = records[change.id]
        switch (current, change.baseVersion) {
        case (nil, nil): return nil
        case (nil, _?): return SyncServerPushResult(id: change.id, status: "conflict")
        case let (current?, base) where base == current.version: return nil
        case let (current?, _):
            return SyncServerPushResult(
                id: change.id,
                status: "conflict",
                current: SyncServerRecord(
                    id: change.id,
                    version: current.version,
                    deleted: current.deleted,
                    keyVersion: 1,
                    payload: current.payload,
                ),
            )
        }
    }

    private func apply(_ change: SyncServerChange) -> SyncServerPushResult {
        if let conflict = conflict(change) {
            return conflict
        }
        write(change.id, deleted: change.deleted, payload: change.payload)
        return SyncServerPushResult(id: change.id, status: "applied", version: counter)
    }

    private func write(_ id: UUID, deleted: Bool, payload: String) {
        counter += 1
        records[id] = Record(version: counter, deleted: deleted, payload: payload)
    }

    /// The sync state of a Mac that read everything, without the records of `hidden`.
    func syncState(hiding hidden: Set<UUID> = []) throws -> SyncState {
        var state = SyncState()
        for (id, record) in records where !hidden.contains(id) {
            let content = try SyncCoding.decoder().decode(
                SyncContent.self,
                from: SyncCrypto.decryptRecord(record.payload, id: id, keyVersion: 1, dataKey: dataKey),
            )
            state.entries[id] = SyncEntry(type: content.type, version: record.version, remote: content)
        }
        return state
    }

    // MARK: Misbehaving

    /// What code with the data key only can write: a deletion of any record.
    func forgeDeletion(of id: UUID, type: String) throws {
        let content = SyncContent.deletion(of: type, schema: 1, modifiedAt: .now, modifiedBy: UUID())
        try write(
            id,
            deleted: true,
            payload: SyncCrypto.encryptRecord(SyncCoding.encoder().encode(content), id: id, keyVersion: 1, dataKey: dataKey),
        )
    }

    /// The records as they are now, to show them again later (a restored backup, or a server that lies).
    func snapshot() -> [UUID: Record] {
        records
    }

    func restore(_ snapshot: [UUID: Record]) {
        records = snapshot
        counter += 1
    }
}

extension SyncServerPushResult {
    init(id: UUID, status: String, version: Int? = nil, current: SyncServerRecord? = nil) {
        self.init(id: id, status: status, version: version, current: current, code: nil)
    }
}
