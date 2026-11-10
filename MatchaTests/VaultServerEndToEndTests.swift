import Foundation
@testable import Matcha
import Testing

/// The vault between two Macs through a real sync server (`VAULT.md` § 5), run only when one is given, open to
/// registration (same variable as `SyncServerEndToEndTests`): the first Mac creates the account, its vault opens with
/// the key of the creation and writes a login; the second signs in, its vault opens with the key of the sign-in,
/// verifies the server's root and shows the login; a change on the second comes back to the first.
@MainActor
struct VaultServerEndToEndTests {
    private let testKeychain = TestKeychain()
    private let testDefaults = TestDefaults("VaultServerEndToEndTests")
    private let server = ProcessInfo.processInfo.environment["MATCHA_SYNC_SERVER"]
    private nonisolated static let hasServer = ProcessInfo.processInfo.environment["MATCHA_SYNC_SERVER"] != nil
    private let password = "un mot de passe assez long, 2026"

    private struct Mac {
        let sync: SyncService
        let vault: VaultService
        let keychain: SyncKeychain
    }

    private func makeMac() throws -> Mac {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let keychain = testKeychain.make()
        let sync = SyncService(defaults: testDefaults.make(), keychain: keychain, extensions: nil, directory: nil)
        let vault = VaultService(defaults: testDefaults.make())
        sync.vault = vault
        sync.onVaultRootKey = { key in Task { await vault.open(rootKey: key) } }
        sync.start(session: session)
        return Mac(sync: sync, vault: vault, keychain: keychain)
    }

    @Test(.enabled(if: hasServer, "No sync server given (MATCHA_SYNC_SERVER)"))
    func `a login written on one Mac is verified and read on the other`() async throws {
        let server = try #require(server)
        let first = try makeMac()
        let second = try makeMac()
        defer {
            first.keychain.removeDevice()
            second.keychain.removeDevice()
        }
        let endpoint = try await first.sync.checkServer(server)
        #expect(endpoint.info.hasVault)
        let email = "vault-\(UUID().uuidString.prefix(8).lowercased())@example.com"
        let kit = try await first.sync.createAccount(on: endpoint, email: email, password: password, invitation: nil)
        first.sync.recoveryKitSaved()
        try await waitUntil(timeout: .seconds(20)) { first.vault.isUnlocked }

        var login = VaultItemContent()
        login.overview.category = .login
        login.overview.title = "Example"
        login.overview.urls = ["https://example.com/login"]
        login.details.updateCredential(VaultCredentialType.basicAuth) { entry in
            entry.set("username", "jeremy")
            entry.set("password", "première valeur")
        }
        let id = try first.vault.save(login)
        await first.vault.writeTask?.value
        try await waitUntil(timeout: .seconds(20)) { first.vault.items.first?.isPending == false }

        let secretKey = try #require(SyncSecretKey(text: kit.secretKey))
        try await second.sync.signIn(on: endpoint, email: email, password: password, secretKey: secretKey)
        try await waitUntil(timeout: .seconds(30)) { second.vault.items.map(\.id) == [id] }
        #expect(try second.vault.fillValues(of: id).password == "première valeur")

        // A change on the second Mac reaches the first, the old value in its history.
        var changed = try second.vault.content(of: id)
        changed.details.updateCredential(VaultCredentialType.basicAuth) { $0.set("password", "seconde valeur") }
        try second.vault.save(changed, id: id)
        await second.vault.writeTask?.value
        await first.sync.coordinator?.syncNow()
        try await waitUntil(timeout: .seconds(30)) { (try? first.vault.fillValues(of: id).password) == "seconde valeur" }
        #expect(try first.vault.content(of: id).details.history.map(\.value).contains("première valeur"))
        #expect(first.vault.notice == nil)

        try await first.sync.deleteAccount(password: password)
    }
}
