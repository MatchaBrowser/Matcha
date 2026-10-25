import CryptoKit
import Foundation
@testable import Matcha
import Testing

/// The sync account on this Mac (tasks 7.7 and 7.9, `SYNC.md` § 3 and § 5), against a fake server: creation, recovery
/// kit, sync started, revoked device, sign-out.
@MainActor
struct SyncServiceTests {
    /// Fake server keeping what an account needs: its key envelope, and the records pushed.
    private final class FakeServer: @unchecked Sendable {
        private let lock = NSLock()
        private var wrappedAccountKey = ""
        private var records: [[String: Any]] = []
        let accountID = UUID()
        /// The identity of another device, given to this Mac at sign-in (review SY19).
        var imposedDevice: UUID?

        func handle(_ request: URLRequest, _ body: Data) throws -> MockResponse {
            let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/server"):
                return try MockURLProtocol.json(200, ["api": 1, "registration": "invitation", "features": ["blobs"]])
            case ("POST", "/api/v1/accounts"):
                guard object["invitation"] as? String == "K7QD-2MXP" else {
                    return MockURLProtocol.problem(403, "invitation_required")
                }
                lock.withLock { wrappedAccountKey = object["wrappedAccountKey"] as? String ?? "" }
                let device = object["device"] as? [String: Any]
                return try MockURLProtocol.json(201, [
                    "accountId": accountID.uuidString,
                    "deviceId": imposedDevice?.uuidString ?? device?["id"] ?? "",
                    "accessToken": "access",
                    "refreshToken": "refresh",
                    "expiresIn": 900,
                    "wrappedAccountKey": lock.withLock { wrappedAccountKey },
                    "keyVersion": 1,
                ])
            case ("POST", "/api/v1/sync/push"):
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer access" else {
                    return MockURLProtocol.problem(401, "device_revoked")
                }
                let changes = object["changes"] as? [[String: Any]] ?? []
                let results = lock.withLock { () -> [[String: Any]] in
                    changes.map { change in
                        records.append(change)
                        return ["id": change["id"] ?? "", "status": "applied", "version": records.count]
                    }
                }
                return try MockURLProtocol.json(200, ["results": results])
            case ("GET", "/api/v1/sync/changes"):
                return try MockURLProtocol.json(200, ["changes": [] as [Any], "cursor": "c_0", "hasMore": false])
            case ("POST", "/api/v1/auth/logout"):
                return MockResponse(status: 204)
            default:
                return MockURLProtocol.problem(404, "not_found")
            }
        }

        var recordCount: Int {
            lock.withLock { records.count }
        }
    }

    @Test func `an account is created, syncs once its kit is saved, and stops when revoked`() async throws {
        let server = FakeServer()
        let (host, urlSession) = MockURLProtocol.serve { request, body in try server.handle(request, body) }
        let defaults = try #require(UserDefaults(suiteName: "SyncServiceTests-\(UUID().uuidString)"))
        let keychain = SyncKeychain(service: "com.matchabrowser.matcha.sync.tests.\(UUID().uuidString)")
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let service = SyncService(defaults: defaults, keychain: keychain, extensions: nil, directory: nil, apiSession: urlSession)
        service.start(session: session)
        #expect(!service.isActive)

        // The reference server answers under /api: found from the bare address.
        let endpoint = try await service.checkServer("https://\(host)")
        let address = endpoint.address
        #expect(address.normalized == "https://\(host)/api")
        #expect(endpoint.info.requiresInvitation)
        await #expect(throws: SyncServerError(status: 403, code: "invitation_required")) {
            _ = try await service.createAccount(
                on: endpoint,
                email: "Jeremy@Example.com ",
                password: "un mot de passe assez long",
                invitation: nil,
            )
        }
        let kit = try await service.createAccount(
            on: endpoint,
            email: "Jeremy@Example.com ",
            password: "un mot de passe assez long",
            invitation: "K7QD-2MXP",
        )
        #expect(kit.email == "jeremy@example.com")
        #expect(SyncRecoveryKey(text: kit.recoveryKey) != nil)
        // Nothing syncs before the kit is saved, which is remembered across launches (review SY12).
        #expect(!service.isActive)
        #expect(service.configuration.isRecoveryKitUnsaved)
        #expect(SyncConfiguration.load(from: defaults).isRecoveryKitUnsaved)
        #expect(service.configuration.accountID == server.accountID)
        #expect(try keychain.data(for: .accountKey, server: address, accountID: server.accountID) != nil)

        service.recoveryKitSaved()
        #expect(service.isActive)
        #expect(!service.configuration.isRecoveryKitUnsaved)
        await service.coordinator?.syncNow()
        #expect(server.recordCount >= 2)

        // Revoked elsewhere: sync stops, the tokens and the key leave the keychain, the browsing data stays.
        service.sessionEnded(SyncServerError(status: 401, code: "device_revoked"))
        #expect(!service.isActive)
        #expect(service.configuration.signedOutReason == .deviceRevoked)
        #expect(try keychain.data(for: .accountKey, server: address, accountID: server.accountID) == nil)
        #expect(session.spaces.count == 1)

        await service.signOut()
        #expect(service.configuration == SyncConfiguration())
        keychain.removeDevice()
    }

    /// Review SY19: the server can't give this Mac the identity of another device.
    @Test func `a session for another device is refused`() async throws {
        let server = FakeServer()
        server.imposedDevice = UUID()
        let (host, urlSession) = MockURLProtocol.serve { request, body in try server.handle(request, body) }
        let defaults = try #require(UserDefaults(suiteName: "SyncServiceTests-\(UUID().uuidString)"))
        let keychain = SyncKeychain(service: "com.matchabrowser.matcha.sync.tests.\(UUID().uuidString)")
        let service = SyncService(defaults: defaults, keychain: keychain, extensions: nil, directory: nil, apiSession: urlSession)
        let endpoint = try await service.checkServer("https://\(host)")
        await #expect(throws: SyncClientError.unreadableAnswer) {
            _ = try await service.createAccount(
                on: endpoint,
                email: "a@example.com",
                password: "un mot de passe assez long",
                invitation: "K7QD-2MXP",
            )
        }
        #expect(service.configuration.accountID == nil)
        #expect(try keychain.device()?.id != server.imposedDevice)
        keychain.removeDevice()
    }

    /// Review SY35: the states no longer used are deleted at launch, even with sync off.
    @Test func `unused states are cleaned up at launch`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SyncServiceTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = folder.appending(path: "state-ancien.json")
        let recent = folder.appending(path: "extensions-recent.json")
        try Data("{}".utf8).write(to: old)
        try Data("{}".utf8).write(to: recent)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-70 * 24 * 60 * 60)], ofItemAtPath: old.path)
        let defaults = try #require(UserDefaults(suiteName: "SyncServiceTests-\(UUID().uuidString)"))
        let service = SyncService(defaults: defaults, extensions: nil, directory: folder)
        try service.start(session: BrowserSession(container: BrowserSchema.makeContainer(inMemory: true)))
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
    }
}
