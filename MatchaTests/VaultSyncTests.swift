import CryptoKit
import Foundation
@testable import Matcha
import Testing

/// The vault between two Macs and a server (`VAULT.md` § 5): atomic writes, verification, merges without loss, repairs
/// of what code with the data key only deletes, reconciliation of a server that shows an older vault, tombstones; and
/// the vault turned off on a Mac.
@MainActor
struct VaultSyncTests {
    private let testKeychain = TestKeychain()
    private let testDefaults = TestDefaults("VaultSyncTests")
    private let accountKey = SymmetricKey(size: .bits256)
    private let rootKey = SymmetricKey(size: .bits256)
    private let server: VaultTestServer

    init() {
        server = VaultTestServer(dataKey: SyncAccountKeys.dataKey(accountKey: accountKey))
    }

    private func makeMac() async throws -> VaultService {
        let vault = VaultService(defaults: testDefaults.make())
        let server = server
        try vault.syncDidActivate(SyncVaultAccount(
            server: SyncServerAddress.parse("https://sync.example.com").get(),
            accountID: UUID(uuidString: "5D0C7A3E-2B1F-4E8D-9A6C-0F3B7E1D2C54") ?? UUID(),
            client: nil,
            identifiers: SyncIdentifiers(accountKey: accountKey),
            dataKey: server.dataKey,
            deviceID: UUID(),
            keychain: testKeychain.make(),
            stateURL: nil,
            serverHasVault: true,
            requestCycle: {},
            push: { body, key in try server.push(body, key: key) },
        ))
        await vault.open(rootKey: rootKey)
        return vault
    }

    private func sync(_ vault: VaultService, hiding hidden: Set<UUID> = []) async throws {
        try await vault.syncCycleDidFinish(state: server.syncState(hiding: hidden))
    }

    private func login(_ title: String, password: String) -> VaultItemContent {
        var content = VaultItemContent()
        content.overview.category = .login
        content.overview.title = title
        content.overview.urls = ["https://example.com/login"]
        content.details.updateCredential(VaultCredentialType.basicAuth) { entry in
            entry.set("username", "jeremy")
            entry.set("password", password)
        }
        return content
    }

    private func password(of id: UUID, in vault: VaultService) throws -> String {
        try #require(try vault.content(of: id).details.credential(VaultCredentialType.basicAuth)).string("password")
    }

    /// Changes the password of an item as the interface does: on its current content.
    private func change(_ id: UUID, password: String, on vault: VaultService) async throws {
        var content = try vault.content(of: id)
        content.details.updateCredential(VaultCredentialType.basicAuth) { $0.set("password", password) }
        _ = try await save(content, id: id, on: vault)
    }

    private func save(_ content: VaultItemContent, id: UUID? = nil, on vault: VaultService) async throws -> UUID {
        let id = try vault.save(content, id: id)
        await vault.writeTask?.value
        return id
    }

    @Test func `an item written on one Mac is verified and shown on the other`() async throws {
        let (first, second) = try await (makeMac(), makeMac())
        let id = try await save(login("Example", password: "one"), on: first)
        #expect(server.records.count == 3)
        #expect(first.items.first?.isPending == false)

        try await sync(second)
        #expect(second.items.map(\.id) == [id])
        #expect(second.items.first?.isWaiting == false)
        #expect(try password(of: id, in: second) == "one")
        #expect(second.notice == nil)
    }

    @Test func `two Macs changing the same password keep both values`() async throws {
        let (first, second) = try await (makeMac(), makeMac())
        let id = try await save(login("Example", password: "one"), on: first)
        try await sync(second)

        try await change(id, password: "first", on: first)
        // The second Mac writes on the version it read: its root is stale, nothing of it is written.
        try await change(id, password: "second", on: second)
        #expect(second.items.first?.isPending == true)
        // It reads, merges, and writes again.
        try await sync(second)
        #expect(second.items.first?.isPending == false)
        try await sync(first)
        for vault in [first, second] {
            #expect(try password(of: id, in: vault) == "second")
            let history = try vault.content(of: id).details.history.map(\.value)
            #expect(history.contains("first"))
            #expect(history.contains("one"))
        }
    }

    @Test func `a deletion written with the data key only is repaired`() async throws {
        let (first, second) = try await (makeMac(), makeMac())
        let id = try await save(login("Example", password: "one"), on: first)
        try await sync(second)

        try server.forgeDeletion(of: id, type: VaultServerView.itemType)
        try await sync(second)
        #expect(server.records[id]?.deleted == false)
        #expect(second.notice == .completedFromThisMac)
        try await sync(first)
        #expect(try password(of: id, in: first) == "one")
        #expect(first.items.first?.isWaiting == false)
    }

    @Test func `an older vault shown by the server is completed from the Mac that saw it`() async throws {
        let (first, second) = try await (makeMac(), makeMac())
        let older = try await save(login("Older", password: "one"), on: first)
        try await sync(second)
        let backup = server.snapshot()
        let newer = try await save(login("Newer", password: "two"), on: first)
        try await sync(second)
        #expect(Set(second.items.map(\.id)) == [older, newer])

        // The server goes back to its backup: the newer item and root are gone.
        server.restore(backup)
        try await sync(second)
        #expect(second.notice == .completedFromThisMac)
        // A Mac that never saw the newer item gets it back.
        let third = try await makeMac()
        try await sync(third)
        #expect(Set(third.items.map(\.id)) == [older, newer])
        #expect(try password(of: newer, in: third) == "two")
    }

    @Test func `an item deleted for good leaves a tombstone, not a divergence`() async throws {
        let (first, second) = try await (makeMac(), makeMac())
        let id = try await save(login("Example", password: "one"), on: first)
        try await sync(second)

        try first.setTrashed([id], true)
        await first.writeTask?.value
        try first.deleteForever([id])
        await first.writeTask?.value
        #expect(first.items.isEmpty)
        try await sync(second)
        #expect(second.items.isEmpty)
        #expect(second.notice == nil)
    }

    @Test func `an item the server hides waits, and is not shown`() async throws {
        let (first, second) = try await (makeMac(), makeMac())
        let shown = try await save(login("Shown", password: "one"), on: first)
        let hidden = try await save(login("Hidden", password: "two"), on: first)
        try await sync(second, hiding: [hidden])
        #expect(second.items.map(\.id) == [shown])
        #expect(second.notice == .itemsWaiting)
        try await sync(second)
        #expect(Set(second.items.map(\.id)) == [shown, hidden])
        #expect(second.notice == nil)
    }

    @Test func `a vault turned off is locked, offered nowhere, and stays off at the next launch`() async throws {
        let vault = try await makeMac()
        let id = try await save(login("Example", password: "one"), on: vault)
        var changes: [Bool] = []
        vault.onEnabledChange.append { changes.append($0) }

        vault.setEnabled(false)
        #expect(!vault.isUnlocked)
        #expect(vault.items.isEmpty)
        #expect(vault.status == .unavailable(.disabled))
        #expect(!vault.isOffered)
        // Neither an account flow nor the password opens it.
        await vault.open(rootKey: rootKey)
        #expect(!vault.isUnlocked)
        await #expect(throws: VaultError.self) { try await vault.unlock(password: "password") }
        #expect(VaultService(defaults: vault.defaults).status == .unavailable(.disabled))

        // Turned on again: what this Mac kept comes back at the opening.
        vault.setEnabled(true)
        #expect(vault.isOffered)
        await vault.open(rootKey: rootKey)
        #expect(vault.items.map(\.id) == [id])
        #expect(changes == [false, true])
    }
}
