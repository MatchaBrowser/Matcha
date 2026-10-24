import Foundation
@testable import Matcha
import Testing

/// Sync engine (task 7.4): two simulated Macs and an in-memory server.
@MainActor
struct SyncEngineTests {
    private let server = InMemorySyncServer()

    /// Two synced Macs sharing a profile and a Space.
    private struct Pair {
        let macA: SimulatedMac
        let macB: SimulatedMac
        let profile: UUID
        let space: UUID
    }

    private func pair() async throws -> Pair {
        let macA = SimulatedMac(server: server)
        let macB = SimulatedMac(server: server)
        let profile = macA.addProfile("Personnel")
        let space = macA.addSpace("Perso", profile: profile)
        try await macA.sync()
        try await macB.sync()
        return Pair(macA: macA, macB: macB, profile: profile, space: space)
    }

    @Test func `creations, changes and deletions reach the other Mac`() async throws {
        let setup = try await pair()
        let (macA, macB, profile, space) = (setup.macA, setup.macB, setup.profile, setup.space)
        #expect(macB.store.items == macA.store.items)
        #expect(macB.name(of: profile) == "Personnel")

        macA.rename(space, to: "Maison")
        let tab = macA.addTodayTab(in: space, url: "https://example.com")
        try await macA.sync()
        try await macB.sync()
        #expect(macB.name(of: space) == "Maison")
        #expect(macB.url(of: tab)?.absoluteString == "https://example.com")

        macB.store.items[tab] = nil
        try await macB.sync()
        try await macA.sync()
        #expect(macA.store.items[tab] == nil)
        #expect(await server.content(of: tab)?.deleted == true)

        // Nothing echoes back.
        #expect(try await macA.sync()?.sent == 0)
        #expect(try await macB.sync()?.sent == 0)
        #expect(macA.store.items == macB.store.items)
    }

    @Test func `the latest change wins a conflict`() async throws {
        let setup = try await pair()
        let (macA, macB, space) = (setup.macA, setup.macB, setup.space)
        // B writes after A, but sends after it: its change is resent on A's version and wins.
        macA.rename(space, to: "A")
        macB.rename(space, to: "B")
        macB.time = macA.time + 20
        try await macA.sync()
        let report = try await macB.sync()
        #expect(report?.conflicts == 1)
        try await macA.sync()
        #expect(macA.name(of: space) == "B")
        #expect(macB.name(of: space) == "B")

        // A writes later and sends first: B's older change is dropped.
        macA.time = macB.time + 60
        macA.rename(space, to: "A2")
        macB.rename(space, to: "B2")
        try await macA.sync()
        try await macB.sync()
        #expect(macB.name(of: space) == "A2")
        #expect(await server.content(of: space)?.readableFields == macA.store.items[space])
        #expect(try await macB.sync()?.sent == 0)
    }

    @Test func `a newer change recreates a deleted record`() async throws {
        let setup = try await pair()
        let (macA, macB, space) = (setup.macA, setup.macB, setup.space)
        macA.store.items[space] = nil
        try await macA.sync()
        macB.time = macA.time + 30
        macB.rename(space, to: "Gardé")
        try await macB.sync()
        try await macA.sync()
        #expect(macA.name(of: space) == "Gardé")
    }

    @Test func `a record waits for its missing parent`() async throws {
        let setup = try await pair()
        let (macA, macB, profile) = (setup.macA, setup.macB, setup.profile)
        // A sends a tab whose Space has not been sent yet.
        let later = UUID()
        let tab = macA.addTodayTab(in: later, url: "https://example.com")
        try await macA.sync()
        try await macB.sync()
        #expect(macB.store.items[tab] == nil)
        // The pending tab is not taken for a deletion.
        #expect(try await macB.sync()?.sent == 0)
        #expect(await server.content(of: tab)?.deleted == false)

        macA.store.items[later] = .space(SyncSpaceFields(
            name: "Plus tard",
            symbol: "circle.fill",
            theme: nil,
            order: 1,
            profileId: profile,
        ))
        try await macA.sync()
        try await macB.sync()
        #expect(macB.store.items[later] != nil)
        #expect(macB.url(of: tab)?.absoluteString == "https://example.com")
    }

    @Test func `a today tab that changes page waits to be stable`() async throws {
        let setup = try await pair()
        let (macA, macB, space) = (setup.macA, setup.macB, setup.space)
        let tab = macA.addTodayTab(in: space, url: "https://example.com/1")
        try await macA.sync()
        try await macB.sync()

        macA.store.items[tab] = .tab(macA.todayTab(in: space, url: "https://example.com/2"))
        #expect(try await macA.sync(after: 1)?.sent == 0)
        #expect(macA.engine.nextCheck == macA.time + SyncChangeDetector.stability)
        #expect(try await macA.sync(after: 5)?.sent == 1)
        try await macB.sync()
        #expect(macB.url(of: tab)?.absoluteString == "https://example.com/2")

        // A page that keeps changing is sent after 30 seconds.
        var sent = 0
        for step in 3 ... 12 {
            macA.store.items[tab] = .tab(macA.todayTab(in: space, url: "https://example.com/\(step)"))
            sent += try await macA.sync(after: 4)?.sent ?? 0
        }
        #expect(sent == 1)

        // Moving the tab is sent right away.
        try await macA.sync(after: 10)
        macA.store.items[tab] = .tab(macA.todayTab(in: space, url: "https://example.com/12", order: 5))
        #expect(try await macA.sync(after: 1)?.sent == 1)
    }

    @Test func `a refused change is not sent again until it changes`() async throws {
        let setup = try await pair()
        let (macA, space) = (setup.macA, setup.space)
        let tab = macA.addTodayTab(in: space, url: "https://example.com/trop-gros")
        await server.refuse(tab)
        #expect(try await macA.sync()?.sent == 0)
        #expect(try await macA.sync()?.sent == 0)
        #expect(await server.content(of: tab) == nil)

        await server.unrefuse(tab)
        macA.store.items[tab] = .tab(macA.todayTab(in: space, url: "https://example.com/plus-petit", order: 1))
        #expect(try await macA.sync()?.sent == 1)
    }

    @Test func `content from a newer Matcha or unreadable is never overwritten`() async throws {
        let setup = try await pair()
        let (macA, macB) = (setup.macA, setup.macB)
        let setting = SyncIdentifiers.testAccount.setting("searchEngine")
        let future = SyncContent(
            type: "setting",
            schema: 2,
            modifiedAt: macA.time,
            modifiedBy: UUID(),
            deleted: false,
            fields: .object(["key": .string("searchEngine"), "value": .object(["engine": .string("kagi")])]),
        )
        await server.write(setting, future)
        let unreadable = UUID()
        await server.write(unreadable, nil)
        macB.store.items[setting] = .setting(SyncSettingFields(key: "searchEngine", value: .string("bing")))
        try await macB.sync()
        #expect(macB.store.items[setting] == .setting(SyncSettingFields(key: "searchEngine", value: .string("bing"))))
        #expect(await server.content(of: setting) == future)
        #expect(macB.store.items[unreadable] == nil)
    }

    @Test func `an expired cursor rereads everything and deletes nothing on an absence`() async throws {
        let setup = try await pair()
        let (macA, macB, space) = (setup.macA, setup.macB, setup.space)
        let kept = macA.addTodayTab(in: space, url: "https://example.com/garde")
        let closed = macA.addTodayTab(in: space, url: "https://example.com/ferme", order: 1)
        try await macA.sync()
        try await macB.sync()
        macA.store.items[closed] = nil
        try await macA.sync()
        await server.purgeDeletions()

        // The server no longer knows the deletion: B keeps the tab and sends it again, as SYNC.md § 5 accepts for a Mac
        // that missed a purged deletion; only an encrypted deletion deletes.
        try await macB.sync()
        #expect(macB.store.items[kept] != nil)
        #expect(macB.store.items[closed] != nil)
        #expect(await server.content(of: closed)?.deleted == false)
        #expect(try await macB.sync()?.sent == 0)
    }

    @Test func `changes go and come in small batches`() async throws {
        let macA = SimulatedMac(server: server, maxChangesPerPush: 2)
        let macB = SimulatedMac(server: server)
        await server.setPageSize(2)
        let profile = macA.addProfile("Personnel")
        let space = macA.addSpace("Perso", profile: profile)
        for order in 0 ..< 5 {
            macA.addTodayTab(in: space, url: "https://example.com/\(order)", order: Double(order))
        }
        #expect(try await macA.sync()?.sent == 7)
        try await macB.sync()
        #expect(macB.store.items == macA.store.items)
    }

    @Test func `the state survives a relaunch`() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "sync-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = MemorySyncStore()
        let transport = InMemorySyncTransport(server: server)
        let first = SyncEngine(store: store, transport: transport, identifiers: .testAccount, file: SyncStateFile(url: url))
        store.items[UUID()] = .profile(SyncProfileFields(name: "Personnel", order: 0))
        try await first.sync()

        let relaunched = SyncEngine(store: store, transport: transport, identifiers: .testAccount, file: SyncStateFile(url: url))
        #expect(relaunched.state == first.state)
        #expect(try await relaunched.sync()?.sent == 0)
    }
}
