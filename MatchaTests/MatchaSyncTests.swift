import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Two Matcha sessions synced by the engine and an in-memory server (task 7.4): the second Mac gets back the
/// Spaces, folders, favorites, pinned tabs and settings of the first one, and sees its today tabs.
@MainActor
struct MatchaSyncTests {
    private let testDefaults = TestDefaults("MatchaSyncTests")
    private let server = InMemorySyncServer()

    /// A Mac: its session, its settings, its engine.
    @MainActor
    private struct Mac {
        let session: BrowserSession
        let defaults: UserDefaults
        let engine: SyncEngine

        var home: SpaceSession? {
            session.spaces.first
        }
    }

    /// `device`: this Mac in sync, which then publishes its today tabs (`deviceTabs`).
    private func makeMac(device: SyncDeviceDescription? = nil) throws -> Mac {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let defaults = testDefaults.make()
        let engine = SyncEngine(
            store: MatchaSyncStore(session: session, defaults: defaults, identifiers: .testAccount, device: device),
            transport: InMemorySyncTransport(server: server),
            identifiers: .testAccount,
            file: SyncStateFile(url: nil),
            deviceID: device?.id,
        )
        if let home = session.spaces.first {
            session.showFavorites(in: home)
        }
        return Mac(session: session, defaults: defaults, engine: engine)
    }

    @Test func `a second Mac finds the data of the first`() async throws {
        let first = try makeMac()
        let home = try #require(first.home)
        first.session.renameSpace(home, to: "Maison")
        let work = first.session.addSpace(inProfileOf: home)
        let pinned = home.tabManager.newTab(url: URL(string: "https://example.com/epingle"), select: false)
        home.tabManager.setPlace(pinned, to: .pinned)
        let folder = home.tabManager.newFolder()
        home.tabManager.renameFolder(folder, to: "Projets")
        home.tabManager.move(pinned, to: .pinned(folder: folder, index: 0))
        let favorite = home.tabManager.newTab(url: URL(string: "https://example.com/favori"), select: false)
        home.tabManager.setPlace(favorite, to: .favorite)
        let today = work.tabManager.newTab(url: URL(string: "https://example.com/jour"), select: false)
        first.defaults.set("duckDuckGo", forKey: BrowserSettings.Key.searchEngine)
        first.session.saveAll()
        try await first.engine.sync()

        let second = try makeMac()
        try await second.engine.sync()
        #expect(second.session.spaces.map(\.record.name) == ["Maison", work.record.name])
        #expect(second.session.profiles.map(\.id) == first.session.profiles.map(\.id))
        let mirror = try #require(second.session.spaces.first)
        #expect(mirror.tabManager.layout.folderEntries.map(\.name) == ["Projets"])
        #expect(mirror.tabManager.layout.positions[pinned.id]?.folderID == folder)
        #expect(mirror.tabManager.favoriteTabs.map(\.id) == [favorite.id])
        // Today tabs stay on each Mac (`SYNC.md` § 2.4).
        #expect(today.url != nil)
        #expect(second.session.spaces.last?.tabManager.todayTabs.isEmpty == true)
        #expect(second.defaults.string(forKey: BrowserSettings.Key.searchEngine) == "duckDuckGo")

        // Then in the other direction, without echoing anything back.
        #expect(try await second.engine.sync()?.sent == 0)
        second.session.renameSpace(mirror, to: "Chez moi")
        try await second.engine.sync()
        try await first.engine.sync()
        #expect(home.record.name == "Chez moi")
        #expect(try await first.engine.sync()?.sent == 0)
    }

    /// `SYNC.md` § 2.4: each Mac sees the other's today tabs, without them entering its sidebar.
    @Test func `each Mac sees the today tabs of the other`() async throws {
        let first = try makeMac(device: SyncDeviceDescription(id: UUID(), name: "MacBook"))
        let home = try #require(first.home)
        home.tabManager.newTab(url: URL(string: "https://example.com/reading"))
        first.session.saveAll()
        try await first.engine.sync()

        let second = try makeMac(device: SyncDeviceDescription(id: UUID(), name: "iMac"))
        try await second.engine.sync()
        let seen = OtherMac.all(in: second.engine.state, now: .now)
        #expect(seen.map(\.name) == ["MacBook"])
        #expect(seen.first?.spaces.first?.tabs.map(\.url.absoluteString) == ["https://example.com/reading"])
        let secondTodayTabs = second.session.spaces.flatMap(\.tabManager.todayTabs)
        #expect(secondTodayTabs.isEmpty)
        // The second Mac has no web tab: nothing to show on the first.
        try await first.engine.sync()
        #expect(OtherMac.all(in: first.engine.state, now: .now).isEmpty)
    }
}
