import Foundation
@testable import Matcha
import Testing

/// Transport whose `failing`th push (counted from 1) fails, as a network cut between two batches.
private struct FailingTransport: SyncTransport {
    actor Count {
        var pushes = 0
        var failing: Int?

        func next() -> Bool {
            pushes += 1
            return pushes == failing
        }

        func fail(at push: Int) {
            failing = pushes + push
        }
    }

    let server: InMemorySyncServer
    let count = Count()
    var maxChangesPerPush = 1

    func push(_ batch: SyncPreparedBatch) async throws -> [SyncPushResult] {
        if await count.next() {
            throw URLError(.networkConnectionLost)
        }
        return await server.push(batch)
    }

    func changes(since cursor: String?) async throws -> SyncChangePage {
        try await server.changes(since: cursor)
    }

    var supportsBlobs: Bool {
        false
    }

    func putBlob(_: Data, id _: UUID) async throws {}

    func blob(id _: UUID) async throws -> Data {
        throw SyncTransportError.blobNotFound
    }

    func deleteBlob(id _: UUID) async throws {}
}

/// Something to do the next time changes are read, once (a change made here during a cycle).
@MainActor
private final class Hook {
    var action: (() -> Void)?

    func run() {
        let action = action
        self.action = nil
        action?()
    }
}

/// Transport whose clock lead is `lead`, and which runs `hook` before reading changes.
private struct ScriptedTransport: SyncTransport {
    let server: InMemorySyncServer
    var lead: TimeInterval?
    var hook = Hook()
    var maxChangesPerPush = 500

    func push(_ batch: SyncPreparedBatch) async throws -> [SyncPushResult] {
        await server.push(batch)
    }

    func changes(since cursor: String?) async throws -> SyncChangePage {
        hook.run()
        return try await server.changes(since: cursor)
    }

    var supportsBlobs: Bool {
        false
    }

    func putBlob(_: Data, id _: UUID) async throws {}

    func blob(id _: UUID) async throws -> Data {
        throw SyncTransportError.blobNotFound
    }

    func deleteBlob(id _: UUID) async throws {}

    func clockLead() async -> TimeInterval? {
        lead
    }
}

/// The engine's fixes of the review (section SY), between simulated Macs and an in-memory server.
@MainActor
struct SyncEngineReviewTests {
    private let server = InMemorySyncServer()

    private func profile(_ mac: SimulatedMac, _ id: UUID) -> SyncProfileFields? {
        if case let .profile(fields) = mac.store.items[id] {
            return fields
        }
        return nil
    }

    private func serverProfile(_ id: UUID) async -> SyncProfileFields? {
        guard let content = await server.content(of: id), case let .profile(fields) = content.readableFields else {
            return nil
        }
        return fields
    }

    /// Review SY5: a conflict won leaves again on top of the other Mac's content, with only this Mac's changed fields.
    @Test func `a conflict won keeps the other Mac's changes`() async throws {
        let first = SimulatedMac(server: server)
        let second = SimulatedMac(server: server)
        let id = first.addProfile("Perso")
        try await first.sync()
        try await second.sync()

        first.rename(id, to: "Maison")
        try await first.sync()
        second.time = first.time + 100
        second.store.items[id] = .profile(SyncProfileFields(name: "Perso", order: 5))
        try await second.sync()

        #expect(await serverProfile(id) == SyncProfileFields(name: "Maison", order: 5))
        #expect(profile(second, id) == SyncProfileFields(name: "Maison", order: 5))
    }

    /// Review SY6: a content won in a first batch is applied, even when a later batch fails.
    @Test func `a batch that fails doesn't lose what an earlier one received`() async throws {
        let first = SimulatedMac(server: server)
        let transport = FailingTransport(server: server)
        let second = SimulatedMac(server: server, transport: transport)
        // Batches leave by identifier: the first renamed first.
        let one = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let two = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        first.store.items[one] = .profile(SyncProfileFields(name: "Un", order: 1))
        first.store.items[two] = .profile(SyncProfileFields(name: "Deux", order: 2))
        try await first.sync()
        try await second.sync()

        // The second Mac renames both, before the first renames the first one.
        second.rename(one, to: "Un ici")
        second.rename(two, to: "Deux ici")
        first.time = second.time + 100
        first.rename(one, to: "Un là-bas")
        try await first.sync(after: 0)
        await transport.count.fail(at: 2)
        await #expect(throws: URLError.self) { try await second.sync(after: 0) }
        #expect(second.name(of: one) == "Un là-bas")

        // Nothing is lost for the next cycle.
        try await second.sync()
        #expect(second.name(of: one) == "Un là-bas")
        #expect(await serverProfile(two)?.name == "Deux ici")
    }

    /// Review SY7: signed out while the first sync's question waits, nothing is applied nor saved.
    @Test func `a cycle cancelled while its question waits applies and saves nothing`() async throws {
        let first = SimulatedMac(server: server)
        _ = first.addProfile("Perso")
        try await first.sync()
        let folder = FileManager.default.temporaryDirectory.appending(path: "SyncEngineReviewTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = SyncStateFile(url: folder.appending(path: "state.json"))
        let store = MemorySyncStore()
        store.items[UUID()] = .profile(SyncProfileFields(name: "Ici", order: 0))
        let engine = SyncEngine(store: store, transport: InMemorySyncTransport(server: server), identifiers: .testAccount, file: file)
        var answer: CheckedContinuation<Void, Never>?
        engine.chooseFirstSync = {
            await withCheckedContinuation { answer = $0 }
            return .merge
        }
        let cycle = Task { try await engine.sync() }
        try await waitUntil { answer != nil }
        cycle.cancel()
        answer?.resume()
        await #expect(throws: CancellationError.self) { try await cycle.value }
        #expect(store.items.count == 1)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "state.json").path))
    }

    /// Review SY9: a clock more than a day ahead sends nothing, from the first cycle after a launch.
    @Test func `a clock far ahead sends nothing from the first cycle`() async throws {
        let mac = SimulatedMac(server: server, transport: ScriptedTransport(server: server, lead: 2 * 24 * 60 * 60))
        _ = mac.addProfile("Perso")
        try await mac.sync()
        #expect(await server.records.isEmpty)
        #expect(mac.engine.isSendingPaused)
    }

    /// Review SY10: after the server is restored from a backup, the newer versions and the deletions it lost leave
    /// again.
    @Test func `a restored server gets the newer versions and the lost deletions back`() async throws {
        let mac = SimulatedMac(server: server)
        let kept = mac.addProfile("Gardé")
        let deleted = mac.addProfile("Supprimé")
        try await mac.sync()
        let backup = await server.records

        mac.rename(kept, to: "Renommé")
        mac.store.items[deleted] = nil
        try await mac.sync()
        await server.restore(backup)
        try await mac.sync()

        #expect(await serverProfile(kept)?.name == "Renommé")
        #expect(await server.content(of: deleted)?.deleted == true)
    }

    /// Review SY17: a record waiting for its parent is tried again when the parent arrives, not at every read.
    @Test func `an orphan is tried again only when its parent arrives`() async throws {
        let first = SimulatedMac(server: server)
        let profileID = first.addProfile("Perso")
        let space = first.addSpace("Travail", profile: profileID)
        let tab = first.addPinnedTab(in: space, url: "https://example.com")
        try await first.sync()
        // The second Mac only gets the tab: its Space comes later.
        let spaceRecord = await server.records[space]
        await server.forget(space)
        let second = SimulatedMac(server: server)
        try await second.sync()
        try await second.sync()
        let tries = second.store.applied.count { $0.id == tab }
        #expect(tries == 1)

        if let content = spaceRecord?.content {
            await server.write(space, content)
        }
        try await second.sync()
        #expect(second.store.items[tab] != nil)
    }

    /// Review SY23: a change made here while a cycle reads the others' is kept, merged, and sent.
    @Test func `a change made during a cycle survives the change received`() async throws {
        let first = SimulatedMac(server: server)
        let id = first.addProfile("Perso")
        try await first.sync()
        let transport = ScriptedTransport(server: server)
        let second = SimulatedMac(server: server, transport: transport)
        try await second.sync()
        first.rename(id, to: "Maison")
        try await first.sync()

        // The order changes here once this Mac was read, while the cycle reads the other's renaming.
        transport.hook.action = { second.store.items[id] = .profile(SyncProfileFields(name: "Perso", order: 7)) }
        try await second.sync()
        #expect(profile(second, id) == SyncProfileFields(name: "Maison", order: 7))
        #expect(await serverProfile(id) == SyncProfileFields(name: "Maison", order: 7))
    }

    /// Review SY32: a pinned tab whose folder was deleted goes to the root of its Space, and the move is sent.
    @Test func `a tab of a deleted folder goes to the root, and the move is sent`() async throws {
        let first = SimulatedMac(server: server)
        let profileID = first.addProfile("Perso")
        let space = first.addSpace("Travail", profile: profileID)
        let folder = UUID()
        first.store.items[folder] = .folder(SyncFolderFields(name: "Projets", order: 0, isCollapsed: false, spaceId: space))
        let tab = UUID()
        var fields = first.pinnedTab(in: space, url: "https://example.com")
        fields.folderId = folder
        first.store.items[tab] = .tab(fields)
        try await first.sync()
        let second = SimulatedMac(server: server)
        try await second.sync()

        // The first Mac deletes the folder and renames the tab, in the same cycle; the tab still names its folder.
        first.store.items[folder] = nil
        fields.title = "Renommé"
        first.store.items[tab] = .tab(fields)
        try await first.sync()
        try await second.sync()

        guard case let .tab(received) = second.store.items[tab] else {
            Issue.record("Tab missing")
            return
        }
        #expect(received.folderId == nil && received.title == "Renommé")
        guard case let .tab(sent) = await server.content(of: tab)?.readableFields else {
            Issue.record("Tab missing on the server")
            return
        }
        #expect(sent.folderId == nil)
    }

    /// Review SY1: an extension installed from an offer doesn't send back its first state: the private windows and the
    /// permissions of the Mac it comes from stay.
    @Test func `an extension installed from an offer sends nothing back`() async throws {
        let first = SimulatedMac(server: server)
        let second = SimulatedMac(server: server)
        _ = second.addProfile("Perso")
        let source = SyncExtensionSource.appExtension(
            bundleIdentifier: "com.example.ext",
            appBundleIdentifier: "com.example.app",
            appName: "App",
        )
        func fields(privateWindows: Bool, granted: [String: Date?]) -> SyncExtensionFields {
            SyncExtensionFields(
                identifier: "com.example.ext", name: "Ext", version: "1", source: source, isEnabled: true,
                allowsPrivateWindows: privateWindows, showsButton: true, grantedPermissions: granted, deniedPermissions: [:],
                grantedMatchPatterns: [:], deniedMatchPatterns: [:],
            )
        }
        let installed = fields(privateWindows: true, granted: ["tabs": nil, "cookies": nil])
        let id = SyncIdentifiers.testAccount.webExtension(installed)
        first.store.items[id] = .webExtension(installed)
        try await first.sync()
        try await second.sync()

        // Installed on the second Mac from the offer: its own first state, never sent.
        second.store.items[id] = .webExtension(fields(privateWindows: false, granted: ["tabs": nil]))
        second.store.adopted = [id]
        try await second.sync()
        #expect(await server.content(of: id)?.readableFields == .webExtension(installed))

        // A later change there is merged on top: only the button changes.
        var changed = fields(privateWindows: false, granted: ["tabs": nil])
        changed.showsButton = false
        second.store.items[id] = .webExtension(changed)
        try await second.sync()
        var expected = installed
        expected.showsButton = false
        #expect(await server.content(of: id)?.readableFields == .webExtension(expected))
    }
}
