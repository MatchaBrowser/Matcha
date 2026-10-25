import Foundation
@testable import Matcha
import Testing

/// What the engine protects against (`SYNC.md` § 2.3 and § 5, audit S2, S4, S6): a server that replays or forgets, a
/// lost answer, a mass deletion, an emptied field, an identifier that doesn't match, a full account, an unreadable
/// state file.
@MainActor
struct SyncEngineSafetyTests {
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

    @Test func `an older content replayed by the server is ignored`() async throws {
        let setup = try await pair()
        let (macA, macB, space) = (setup.macA, setup.macB, setup.space)
        let old = await server.content(of: space)
        macA.rename(space, to: "Nouveau")
        try await macA.sync()
        try await macB.sync()
        #expect(macB.name(of: space) == "Nouveau")
        // The server writes the old, authentic content again, at a newer version.
        await server.write(space, old)
        try await macB.sync()
        #expect(macB.name(of: space) == "Nouveau")
    }

    @Test func `a batch whose answer was lost is sent again with its key`() async throws {
        let mac = SimulatedMac(server: server, transport: LossyTransport(server: server, losses: .init(1)))
        let profile = mac.addProfile("Personnel")
        await #expect(throws: URLError.self) { try await mac.sync() }
        #expect(mac.engine.state.inFlight != nil)
        #expect(await server.writtenBatches == 1)
        // Sent again exactly as it was: the server gives the same answer, without writing it twice.
        try await mac.sync()
        #expect(mac.engine.state.inFlight == nil)
        #expect(await server.writtenBatches == 1)
        #expect(mac.engine.state.entries[profile]?.version != nil)
        #expect(try await mac.sync()?.sent == 0)
    }

    @Test func `deleting more than half of the account asks first`() async throws {
        let setup = try await pair()
        let (macA, macB, space) = (setup.macA, setup.macB, setup.space)
        let tabs = (0 ..< 60).map { macA.addPinnedTab(in: space, url: "https://example.com/\($0)", order: Double($0)) }
        try await macA.sync()
        try await macB.sync()

        // Refused: the tabs come back from the synced data, nothing is deleted on the server.
        tabs.forEach { macA.store.items[$0] = nil }
        var asked = 0
        macA.engine.confirmMassDeletion = { count in
            asked = count
            return false
        }
        try await macA.sync()
        #expect(asked == 60)
        #expect(tabs.allSatisfy { macA.store.items[$0] != nil })
        #expect(await server.content(of: tabs[0])?.deleted == false)

        // Confirmed: the deletions leave.
        tabs.forEach { macA.store.items[$0] = nil }
        macA.engine.confirmMassDeletion = { _ in true }
        try await macA.sync()
        #expect(await server.content(of: tabs[0])?.deleted == true)
        try await macB.sync()
        #expect(macB.store.items[tabs[0]] == nil)
    }

    @Test func `a field emptied here reaches the other Mac, and unknown fields stay`() async throws {
        let setup = try await pair()
        let (macA, macB, profile, space) = (setup.macA, setup.macB, setup.profile, setup.space)
        macA.store.items[space] = .space(SyncSpaceFields(name: "Perso", symbol: "star.fill", theme: .ocean, order: 0, profileId: profile))
        try await macA.sync()
        try await macB.sync()
        // A newer Matcha added a field: it is kept by the modifications of this one.
        let current = try #require(await server.content(of: space))
        var extended = current
        extended.fields = .object(current.fields.objectValue.merging(["pinnedColor": .string("#FF0000")]) { mine, _ in mine })
        extended.modifiedAt = macA.time + 1
        await server.write(space, extended)
        try await macA.sync()

        macA.store.items[space] = .space(SyncSpaceFields(name: "Perso", symbol: "star.fill", theme: nil, order: 0, profileId: profile))
        try await macA.sync(after: 10)
        try await macB.sync()
        guard case let .space(fields) = macB.store.items[space] else {
            Issue.record("Space missing")
            return
        }
        #expect(fields.theme == nil)
        #expect(await server.content(of: space)?.fields.objectValue["pinnedColor"] == .string("#FF0000"))
    }

    @Test func `a record whose identifier doesn't match its fields is ignored`() async throws {
        let setup = try await pair()
        let (macA, macB) = (setup.macA, setup.macB)
        let forged = SyncContent(
            fields: .setting(SyncSettingFields(key: "searchEngine", value: .string("bing"))),
            modifiedAt: macA.time,
            modifiedBy: UUID(),
        )
        let wrongID = UUID()
        await server.write(wrongID, forged)
        try await macB.sync()
        #expect(macB.store.items[wrongID] == nil)
        #expect(macB.engine.state.entries[wrongID]?.isUnreadable == true)
    }

    @Test func `a record forgotten by the server is sent again as a creation`() async throws {
        let setup = try await pair()
        let (macA, space) = (setup.macA, setup.space)
        await server.forget(space)
        macA.rename(space, to: "Toujours là")
        try await macA.sync()
        #expect(await server.content(of: space)?.readableFields == macA.store.items[space])
    }

    @Test func `a full account keeps the changes, and sends deletions first`() async throws {
        let setup = try await pair()
        let (macA, space) = (setup.macA, setup.space)
        let tab = macA.addPinnedTab(in: space, url: "https://example.com/plein")
        await server.refuse(tab, code: SyncRejectionCode.quotaExceeded)
        #expect(try await macA.sync()?.sent == 0)
        #expect(macA.engine.state.isQuotaExceeded)
        #expect(macA.engine.state.pending[tab] != nil)
        #expect(macA.engine.state.rejected[tab] == nil)

        await server.unrefuse(tab)
        #expect(try await macA.sync()?.sent == 1)
        #expect(!macA.engine.state.isQuotaExceeded)
    }

    @Test func `a batch too big for one request leaves in smaller ones`() async throws {
        let mac = SimulatedMac(server: server, transport: TinyRequestTransport(server: server))
        let profile = mac.addProfile("Personnel")
        let space = mac.addSpace("Perso", profile: profile)
        mac.addPinnedTab(in: space, url: "https://example.com")
        #expect(try await mac.sync()?.sent == 3)
        #expect(mac.engine.state.pending.isEmpty)
    }

    @Test func `an unreadable state file is set aside, and the sync merges without asking`() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "sync-state-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "state.json")
        try Data("not json".utf8).write(to: url)

        let macA = try await pair().macA
        let store = MemorySyncStore()
        store.items[UUID()] = .profile(SyncProfileFields(name: "Travail", order: 1))
        let device = UUID()
        let engine = SyncEngine(
            store: store,
            transport: InMemorySyncTransport(server: server),
            identifiers: .testAccount,
            file: SyncStateFile(url: url),
            deviceID: device,
        )
        #expect(engine.state.mergesWithoutAsking)
        #expect(engine.state.deviceID == device)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.contains("unreadable") })
        var asked = false
        engine.chooseFirstSync = {
            asked = true
            return .replaceRemote
        }
        try await engine.sync()
        #expect(!asked)
        #expect(store.items.count == macA.store.items.count + 1)
    }

    /// Review TS8: changes this Mac couldn't write are read again at the next cycle, the cursor stays before them.
    @Test func `changes that can't be applied are read again`() async throws {
        let setup = try await pair()
        let (macA, macB, space) = (setup.macA, setup.macB, setup.space)
        macA.rename(space, to: "Nouveau")
        try await macA.sync()
        macB.store.applyFailure = CocoaError(.fileWriteUnknown)
        await #expect(throws: CocoaError.self) { try await macB.sync() }
        #expect(macB.name(of: space) == "Perso")

        try await macB.sync()
        #expect(macB.name(of: space) == "Nouveau")
    }
}
