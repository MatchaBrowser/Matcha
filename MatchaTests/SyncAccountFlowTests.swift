import Foundation
@testable import Matcha
import Testing

/// The account flows of `SyncService` (`SYNC.md` § 3.4 to § 3.7, review TS8), between two Macs and a fake server:
/// sign-in, password, identifier and recovery key changes, deletion, devices, forgotten password.
@MainActor
struct SyncAccountFlowTests {
    private let testKeychain = TestKeychain()
    private let testDefaults = TestDefaults("SyncAccountFlowTests")
    private let server = FakeAccountServer()
    private let host: String
    private let urlSession: URLSession

    private static let email = "jeremy@example.com"
    private static let password = "un mot de passe assez long"
    private static let newPassword = "un autre mot de passe assez long"
    private static let invalidCredentials = SyncServerError(status: 401, code: "invalid_credentials")

    init() {
        (host, urlSession) = MockURLProtocol.serve { [server] request, body in try server.handle(request, body) }
    }

    /// A Mac of its own: keychain (so its own device), settings and browsing data.
    @MainActor
    private struct Mac {
        let service: SyncService
        let keychain: SyncKeychain
        let session: BrowserSession

        var accountKey: Data? {
            get throws {
                guard let server = service.configuration.server, let accountID = service.configuration.accountID else {
                    return nil
                }
                return try keychain.data(for: .accountKey, server: server, accountID: accountID)
            }
        }

        var deviceID: UUID? {
            try? keychain.device()?.id
        }
    }

    private func makeMac() throws -> Mac {
        let keychain = testKeychain.make()
        let service = SyncService(
            defaults: testDefaults.make(),
            keychain: keychain,
            extensions: nil,
            directory: nil,
            apiSession: urlSession,
        )
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        service.start(session: session)
        return Mac(service: service, keychain: keychain, session: session)
    }

    private func endpoint(of mac: Mac) async throws -> SyncServerEndpoint {
        try await mac.service.checkServer("https://\(host)")
    }

    /// The first Mac, which created the account and saved its kit.
    private func createAccount() async throws -> (mac: Mac, kit: SyncRecoveryKit) {
        let mac = try makeMac()
        let kit = try await mac.service.createAccount(on: endpoint(of: mac), email: Self.email, password: Self.password, invitation: nil)
        mac.service.recoveryKitSaved()
        #expect(mac.service.isActive)
        return (mac, kit)
    }

    /// A second Mac signed in to the account.
    private func signIn(password: String = Self.password) async throws -> Mac {
        let mac = try makeMac()
        try await mac.service.signIn(on: endpoint(of: mac), email: Self.email, password: password)
        return mac
    }

    /// The next cycle of `mac` meets the end of its session, with `reason`.
    private func expectSignedOut(_ mac: Mac, _ reason: SyncConfiguration.SignedOutReason) async throws {
        await mac.service.coordinator?.syncNow()
        try await waitUntil { !mac.service.isActive }
        #expect(mac.service.configuration.signedOutReason == reason)
        #expect(try mac.accountKey == nil)
    }

    @Test func `a second Mac signs in with the password only`() async throws {
        let (first, _) = try await createAccount()
        let second = try makeMac()
        let endpoint = try await endpoint(of: second)
        await #expect(throws: Self.invalidCredentials) {
            try await second.service.signIn(on: endpoint, email: Self.email, password: "pas le bon mot de passe")
        }
        #expect(!second.service.isActive)
        #expect(server.deviceNames.count == 1)

        // The identifier is normalized as at creation.
        try await second.service.signIn(on: endpoint, email: " Jeremy@Example.COM", password: Self.password)
        #expect(second.service.isActive)
        #expect(second.service.configuration.accountID == server.accountID)
        #expect(try second.accountKey != nil)
        #expect(try second.accountKey == first.accountKey)
        #expect(server.deviceNames.count == 2)
        #expect(first.deviceID != second.deviceID)
    }

    /// `SYNC.md` § 3.6: the account key stays, wrapped again; the other Macs are disconnected.
    @Test func `a new password signs the other Macs out`() async throws {
        let (first, _) = try await createAccount()
        let second = try await signIn()
        await #expect(throws: Self.invalidCredentials) {
            try await first.service.changePassword(current: "pas le bon mot de passe", new: Self.newPassword)
        }
        try await first.service.changePassword(current: Self.password, new: Self.newPassword)
        #expect(first.service.isActive)
        try await expectSignedOut(second, .deviceRevoked)

        await #expect(throws: Self.invalidCredentials) {
            _ = try await signIn(password: Self.password)
        }
        let third = try await signIn(password: Self.newPassword)
        #expect(try third.accountKey == first.accountKey)
    }

    @Test func `a new identifier is the account's from then on`() async throws {
        let (first, _) = try await createAccount()
        await #expect(throws: Self.invalidCredentials) {
            try await first.service.changeEmail(password: "pas le bon mot de passe", to: "nouveau@example.com")
        }
        try await first.service.changeEmail(password: Self.password, to: " Nouveau@Example.com")
        #expect(server.email == "nouveau@example.com")
        #expect(first.service.configuration.email == "nouveau@example.com")
        #expect(first.service.isActive)

        await #expect(throws: Self.invalidCredentials) {
            _ = try await signIn()
        }
        let second = try makeMac()
        try await second.service.signIn(on: endpoint(of: second), email: "nouveau@example.com", password: Self.password)
        #expect(second.service.isActive)
    }

    /// The account goes with its data on the server; each Mac keeps its own (`SYNC.md` § 5).
    @Test func `a deleted account signs every Mac out`() async throws {
        let (first, _) = try await createAccount()
        let second = try await signIn()
        await #expect(throws: Self.invalidCredentials) {
            try await first.service.deleteAccount(password: "pas le bon mot de passe")
        }
        #expect(server.hasAccount)
        try await first.service.deleteAccount(password: Self.password)
        #expect(!server.hasAccount)
        #expect(!first.service.isActive)
        #expect(first.service.configuration.accountID == nil)
        #expect(first.session.spaces.count == 1)
        try await expectSignedOut(second, .accountDeleted)
        #expect(second.session.spaces.count == 1)
    }

    @Test func `devices are renamed and disconnected`() async throws {
        let (first, _) = try await createAccount()
        let second = try await signIn()
        let secondID = try #require(second.deviceID)
        let devices = try await first.service.devices()
        #expect(Set(devices.map(\.id)) == Set([first.deviceID, secondID].compactMap(\.self)))
        #expect(devices.filter { $0.current == true }.map(\.id) == [first.deviceID].compactMap(\.self))

        try await first.service.renameDevice(secondID, to: "Mac du bureau")
        #expect(try await first.service.devices().first { $0.id == secondID }?.name == "Mac du bureau")

        try await first.service.revokeDevice(secondID)
        #expect(try await first.service.devices().map(\.id) == [first.deviceID].compactMap(\.self))
        try await expectSignedOut(second, .deviceRevoked)
        #expect(first.service.isActive)
    }

    /// `SYNC.md` § 3.7: the recovery key opens the account again with a new password; the other Macs are disconnected,
    /// and a new key replaces the old one.
    @Test func `the recovery key recovers the account with a new password`() async throws {
        let (first, kit) = try await createAccount()
        let accountKey = try #require(try first.accountKey)
        let recoveryKey = try #require(SyncRecoveryKey(text: kit.recoveryKey))
        let second = try makeMac()
        let endpoint = try await endpoint(of: second)
        await #expect(throws: Self.invalidCredentials) {
            _ = try await second.service.recover(
                on: endpoint,
                email: Self.email,
                recoveryKey: SyncRecoveryKey.random(),
                newPassword: Self.newPassword,
                newRecoveryKey: true,
            )
        }
        let newKit = try #require(await second.service.recover(
            on: endpoint,
            email: Self.email,
            recoveryKey: recoveryKey,
            newPassword: Self.newPassword,
            newRecoveryKey: true,
        ))
        #expect(newKit.recoveryKey != kit.recoveryKey)
        #expect(second.service.isActive)
        #expect(second.service.configuration.isRecoveryKitUnsaved)
        #expect(try second.accountKey == accountKey)
        try await expectSignedOut(first, .deviceRevoked)

        // The old key and the old password no longer open the account; the new ones do.
        let third = try makeMac()
        await #expect(throws: Self.invalidCredentials) {
            _ = try await third.service.recover(
                on: endpoint,
                email: Self.email,
                recoveryKey: recoveryKey,
                newPassword: Self.password,
                newRecoveryKey: false,
            )
        }
        await #expect(throws: Self.invalidCredentials) {
            _ = try await signIn(password: Self.password)
        }
        #expect(try await third.service.recover(
            on: endpoint,
            email: Self.email,
            recoveryKey: #require(SyncRecoveryKey(text: newKit.recoveryKey)),
            newPassword: Self.password,
            newRecoveryKey: false,
        ) == nil)
        #expect(try third.accountKey == accountKey)
    }

    @Test func `a replaced recovery key leaves the old one useless`() async throws {
        let (first, kit) = try await createAccount()
        await #expect(throws: Self.invalidCredentials) {
            _ = try await first.service.replaceRecoveryKey(password: "pas le bon mot de passe")
        }
        let newKit = try await first.service.replaceRecoveryKey(password: Self.password)
        #expect(newKit.email == Self.email)
        #expect(newKit.recoveryKey != kit.recoveryKey)
        #expect(first.service.configuration.isRecoveryKitUnsaved)
        // Sync goes on while the new kit waits to be saved.
        #expect(first.service.isActive)

        let second = try makeMac()
        let endpoint = try await endpoint(of: second)
        await #expect(throws: Self.invalidCredentials) {
            _ = try await second.service.recover(
                on: endpoint,
                email: Self.email,
                recoveryKey: #require(SyncRecoveryKey(text: kit.recoveryKey)),
                newPassword: Self.newPassword,
                newRecoveryKey: false,
            )
        }
        _ = try await second.service.recover(
            on: endpoint,
            email: Self.email,
            recoveryKey: #require(SyncRecoveryKey(text: newKit.recoveryKey)),
            newPassword: Self.newPassword,
            newRecoveryKey: false,
        )
        #expect(try second.accountKey == first.accountKey)
    }
}
