import CryptoKit
import Foundation
import OSLog

/// Transport to a private (or public) sync server (`SYNC.md` § 3.5 and § 4.6): contents are encrypted on this Mac
/// with the account's data key, bound to their identifier, before leaving. The server never sees a plaintext content.
nonisolated struct SyncServerTransport: SyncTransport {
    /// Version of the account key the contents are encrypted with.
    static let keyVersion = 1

    let client: SyncAPIClient
    let dataKey: SymmetricKey
    let maxChangesPerPush: Int
    /// Size of a request body the server accepts (4 MiB by default).
    let maxRequestBytes: Int
    let supportsBlobs: Bool
    /// Size of an encrypted package the server keeps (21 MiB by default): a larger answer is refused as it comes.
    let maxBlobBytes: Int

    init(client: SyncAPIClient, accountKey: SymmetricKey, server: SyncServerInfo) {
        self.client = client
        dataKey = SyncAccountKeys.dataKey(accountKey: accountKey)
        maxChangesPerPush = min(max(server.limits?.maxChangesPerPush ?? 500, 1), 500)
        maxRequestBytes = server.limits?.maxRequestBytes ?? 4 * 1024 * 1024
        supportsBlobs = server.hasBlobs
        maxBlobBytes = server.maximumBlobBytes
    }

    func prepare(_ changes: [SyncOutgoingChange]) throws -> SyncPreparedBatch {
        let encrypted = try changes.map { change in
            try SyncServerChange(
                id: change.id,
                baseVersion: change.baseVersion,
                deleted: change.content.deleted,
                keyVersion: Self.keyVersion,
                payload: SyncCrypto.encryptRecord(change.content.encoded(), id: change.id, keyVersion: Self.keyVersion, dataKey: dataKey),
            )
        }
        let body = try SyncCoding.encoder().encode(SyncPushRequest(changes: encrypted))
        guard body.count <= maxRequestBytes else {
            throw SyncTransportError.batchTooLarge
        }
        return SyncPreparedBatch(key: UUID(), changes: changes, body: body)
    }

    func push(_ batch: SyncPreparedBatch) async throws -> [SyncPushResult] {
        let response: SyncPushResponse
        do {
            response = try await client.push(body: batch.body, key: batch.key)
        } catch let error as SyncServerError where error.code == SyncServerError.requestTooLarge {
            throw SyncTransportError.batchTooLarge
        }
        return try Self.results(response.results, for: batch.changes).map { result in
            switch result.status {
            case "applied":
                guard let version = result.version else {
                    return .rejected(code: SyncRejectionCode.invalidPayload)
                }
                return .applied(version: version)
            case "conflict":
                return .conflict(current: result.current.map(decrypted))
            default:
                return .rejected(code: result.code ?? SyncRejectionCode.invalidPayload)
            }
        }
    }

    /// The server's result for each change, matched by identifier, never by position (review SY2): a result for
    /// another change, or a current record of another identifier, would apply one record's content under another
    /// (`SYNC.md` § 3.9). One result per change, nothing more: otherwise the answer is unreadable.
    static func results(_ results: [SyncServerPushResult], for changes: [SyncOutgoingChange]) throws -> [SyncServerPushResult] {
        var byID: [UUID: SyncServerPushResult] = [:]
        for result in results {
            guard let id = result.id, byID.updateValue(result, forKey: id) == nil, result.current.map({ $0.id == id }) ?? true else {
                throw SyncClientError.unreadableAnswer
            }
        }
        guard byID.count == changes.count else {
            throw SyncClientError.unreadableAnswer
        }
        return try changes.map { change in
            guard let result = byID[change.id] else {
                throw SyncClientError.unreadableAnswer
            }
            return result
        }
    }

    func changes(since cursor: String?) async throws -> SyncChangePage {
        let response = try await client.changes(since: cursor)
        return SyncChangePage(records: response.changes.map(decrypted), cursor: response.cursor, hasMore: response.hasMore)
    }

    func putBlob(_ data: Data, id: UUID) async throws {
        try await client.putBlob(data, id: id)
    }

    func blob(id: UUID) async throws -> Data {
        try await client.blob(id: id, limit: maxBlobBytes)
    }

    func deleteBlob(id: UUID) async throws {
        try await client.deleteBlob(id: id)
    }

    /// From the last answer's `Date` header; before any answer (first cycle after a launch), from `GET /v1/server`.
    func clockLead() async -> TimeInterval? {
        if let offset = await client.clock.offset {
            return offset
        }
        _ = try? await client.server()
        return await client.clock.offset
    }

    /// The record with its decrypted content; nil content if it can't be opened or read: it is then ignored, never
    /// overwritten. Only the decrypted content counts, never the server's metadata (`deleted`).
    func decrypted(_ record: SyncServerRecord) -> SyncRemoteRecord {
        do {
            let data = try SyncCrypto.decryptRecord(
                record.payload,
                id: record.id,
                keyVersion: record.keyVersion ?? Self.keyVersion,
                dataKey: dataKey,
            )
            return try SyncRemoteRecord(id: record.id, version: record.version, content: SyncContent.decoded(from: data))
        } catch {
            Logger.sync.error("Unreadable record: \(error.logSummary, privacy: .public)")
            return SyncRemoteRecord(id: record.id, version: record.version, content: nil)
        }
    }
}
