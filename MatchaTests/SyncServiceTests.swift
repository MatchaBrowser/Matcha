import CryptoKit
import Foundation
@testable import Matcha
import Testing

/// The sync account on this Mac (tasks 7.7 and 7.9, `SYNC.md` § 3 and § 5), against a fake server: creation, recovery
/// kit, sync started, revoked device, sign-out.
@MainActor
struct SyncServiceTests {
    private let testKeychain = TestKeychain()
    private let testDefaults = TestDefaults("SyncServiceTests")
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

    /// An account created on a fake server, its kit not saved yet: the common setup of the account tests (review TS15).
    private struct SignedUp {
        let server: FakeServer
        let service: SyncService
        let keychain: SyncKeychain
        let defaults: UserDefaults
        let session: BrowserSession
        let address: SyncServerAddress
        let kit: SyncRecoveryKit
    }

    private func signUp() async throws -> SignedUp {
        let server = FakeServer()
        let (host, urlSession) = MockURLProtocol.serve { request, body in try server.handle(request, body) }
        let defaults = testDefaults.make()
        let keychain = testKeychain.make()
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let service = SyncService(defaults: defaults, keychain: keychain, extensions: nil, directory: nil, apiSession: urlSession)
        service.start(session: session)
        #expect(!service.isActive)

        // The reference server answers under /api: found from the bare address.
        let endpoint = try await service.checkServer("https://\(host)")
        #expect(endpoint.address.normalized == "https://\(host)/api")
        #expect(endpoint.info.requiresInvitation)
        await #expect(throws: SyncServerError(status: 403, code: "invitation_required")) {
            _ = try await service.createAccount(on: endpoint, email: "Jeremy@Example.com ", password: Self.password, invitation: nil)
        }
        let kit = try await service.createAccount(
            on: endpoint,
            email: "Jeremy@Example.com ",
            password: Self.password,
            invitation: "K7QD-2MXP",
        )
        return SignedUp(
            server: server,
            service: service,
            keychain: keychain,
            defaults: defaults,
            session: session,
            address: endpoint.address,
            kit: kit,
        )
    }

    private static let password = "un mot de passe assez long"

    @Test func `a new account syncs nothing before its kit is saved`() async throws {
        let account = try await signUp()
        #expect(account.kit.email == "jeremy@example.com")
        #expect(SyncRecoveryKey(text: account.kit.recoveryKey) != nil)
        // Remembered across launches (review SY12).
        #expect(!account.service.isActive)
        #expect(account.service.configuration.isRecoveryKitUnsaved)
        #expect(SyncConfiguration.load(from: account.defaults).isRecoveryKitUnsaved)
        #expect(account.service.configuration.accountID == account.server.accountID)
        #expect(try account.keychain.data(for: .accountKey, server: account.address, accountID: account.server.accountID) != nil)
    }

    @Test func `sync starts once the kit is saved`() async throws {
        let account = try await signUp()
        account.service.recoveryKitSaved()
        #expect(account.service.isActive)
        #expect(!account.service.configuration.isRecoveryKitUnsaved)
        await account.service.coordinator?.syncNow()
        #expect(account.server.recordCount >= 2)
    }

    /// Revoked elsewhere: sync stops, the tokens and the key leave the keychain, the browsing data stays.
    @Test func `a revoked Mac stops syncing and keeps its data`() async throws {
        let account = try await signUp()
        account.service.recoveryKitSaved()
        account.service.sessionEnded(SyncServerError(status: 401, code: "device_revoked"))
        #expect(!account.service.isActive)
        #expect(account.service.configuration.signedOutReason == .deviceRevoked)
        #expect(try account.keychain.data(for: .accountKey, server: account.address, accountID: account.server.accountID) == nil)
        #expect(account.session.spaces.count == 1)

        await account.service.signOut()
        #expect(account.service.configuration == SyncConfiguration())
    }

    /// Review SY19: the server can't give this Mac the identity of another device.
    @Test func `a session for another device is refused`() async throws {
        let server = FakeServer()
        server.imposedDevice = UUID()
        let (host, urlSession) = MockURLProtocol.serve { request, body in try server.handle(request, body) }
        let defaults = testDefaults.make()
        let keychain = testKeychain.make()
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
        let defaults = testDefaults.make()
        let service = SyncService(defaults: defaults, keychain: testKeychain.make(), extensions: nil, directory: folder)
        try service.start(session: BrowserSession(container: BrowserSchema.makeContainer(inMemory: true)))
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
    }
}
