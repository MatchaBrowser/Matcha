import CryptoKit
import Foundation
@testable import Matcha
import Testing

/// The keys of the vault in the account flows (`VAULT.md` § 2.2): drawn with the account, wrapped again with every new
/// password or recovery key, handed to the vault by every flow that has them, between Macs and a fake server.
@MainActor
struct VaultAccountFlowTests {
    private let testKeychain = TestKeychain()
    private let testDefaults = TestDefaults("VaultAccountFlowTests")
    private let server = FakeAccountServer()
    private let host: String
    private let urlSession: URLSession

    private static let email = "jeremy@example.com"
    private static let password = "un mot de passe assez long"
    private static let newPassword = "un autre mot de passe assez long"

    /// A Mac, and the vault root keys its sync handed to the vault.
    @MainActor
    private final class Mac {
        let service: SyncService
        var vaultKeys: [Data] = []

        init(service: SyncService) {
            self.service = service
            service.onVaultRootKey = { [weak self] key in self?.vaultKeys.append(key.withUnsafeBytes { Data($0) }) }
        }
    }

    init() {
        (host, urlSession) = MockURLProtocol.serve { [server] request, body in try server.handle(request, body) }
    }

    private func makeMac() throws -> Mac {
        let service = SyncService(
            defaults: testDefaults.make(),
            keychain: testKeychain.make(),
            extensions: nil,
            directory: nil,
            apiSession: urlSession,
        )
        try service.start(session: BrowserSession(container: BrowserSchema.makeContainer(inMemory: true)))
        return Mac(service: service)
    }

    private func endpoint(of mac: Mac) async throws -> SyncServerEndpoint {
        try await mac.service.checkServer("https://\(host)")
    }

    private func secretKey(of kit: SyncRecoveryKit) throws -> SyncSecretKey {
        try #require(SyncSecretKey(text: kit.secretKey))
    }

    @Test func `every flow hands the same vault root key to the vault`() async throws {
        let first = try makeMac()
        let kit = try await first.service.createAccount(
            on: endpoint(of: first),
            email: Self.email,
            password: Self.password,
            invitation: nil,
        )
        first.service.recoveryKitSaved()
        let vaultKey = try #require(first.vaultKeys.first)
        #expect(try first.service.storedVaultEnvelope()?.kdf.isAcceptable == true)

        let second = try makeMac()
        try await second.service.signIn(on: endpoint(of: second), email: Self.email, password: Self.password, secretKey: secretKey(of: kit))
        #expect(second.vaultKeys == [vaultKey])

        // A new password wraps the same key again: a Mac that signs in with it gets it.
        try await first.service.changePassword(current: Self.password, new: Self.newPassword)
        let third = try makeMac()
        try await third.service.signIn(
            on: endpoint(of: third),
            email: Self.email,
            password: Self.newPassword,
            secretKey: secretKey(of: kit),
        )
        #expect(third.vaultKeys == [vaultKey])

        // A new recovery key wraps it too: a recovery with it gets it.
        let newKit = try await first.service.replaceRecoveryKey(password: Self.newPassword)
        let fourth = try makeMac()
        let recovered = try await fourth.service.recover(
            on: endpoint(of: fourth),
            email: Self.email,
            recoveryKey: #require(SyncRecoveryKey(text: newKit.recoveryKey)),
            newPassword: Self.password,
            newRecoveryKey: false,
        )
        #expect(fourth.vaultKeys == [vaultKey])
        // After the recovery, the new password and the new Secret Key open the same vault.
        let fifth = try makeMac()
        try await fifth.service.signIn(
            on: endpoint(of: fifth),
            email: Self.email,
            password: Self.password,
            secretKey: secretKey(of: recovered),
        )
        #expect(fifth.vaultKeys == [vaultKey])
    }

    @Test func `a wrong current password is refused before the vault key leaves`() async throws {
        let mac = try makeMac()
        _ = try await mac.service.createAccount(on: endpoint(of: mac), email: Self.email, password: Self.password, invitation: nil)
        mac.service.recoveryKitSaved()
        await #expect(throws: SyncServerError(status: 401, code: "invalid_credentials")) {
            try await mac.service.changePassword(current: "pas le bon mot de passe", new: Self.newPassword)
        }
        // The envelope kept is still the one of the current password.
        let envelope = try #require(try mac.service.storedVaultEnvelope())
        let keys = try SyncAccountKeys.passwordKeys(
            password: Self.password,
            secretKey: #require(mac.service.rememberedSecretKey()),
            kdf: envelope.kdf,
        )
        #expect(try VaultCrypto.unwrapRootKey(envelope.wrappedVaultRootKey, with: keys.wrapKey).withUnsafeBytes { Data($0) } == mac
            .vaultKeys.first)
    }
}
