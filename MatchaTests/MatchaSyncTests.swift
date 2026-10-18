import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Deux sessions de Matcha synchronisées par le moteur et un serveur en mémoire (tâche 7.4) : le second Mac retrouve
/// les Spaces, dossiers, favoris, épinglés, onglets du jour et réglages du premier.
@MainActor
struct MatchaSyncTests {
    private let server = InMemorySyncServer()

    /// Un Mac : sa session, ses réglages, son moteur.
    @MainActor
    private struct Mac {
        let session: BrowserSession
        let defaults: UserDefaults
        let engine: SyncEngine

        var home: SpaceSession? {
            session.spaces.first
        }
    }

    private func makeMac() throws -> Mac {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let defaults = try #require(UserDefaults(suiteName: "MatchaSyncTests-\(UUID().uuidString)"))
        let engine = SyncEngine(
            store: MatchaSyncStore(session: session, defaults: defaults),
            transport: InMemorySyncTransport(server: server),
            file: SyncStateFile(url: nil),
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
        let pinned = home.tabManager.newTab(url: URL(string: "about:blank#epingle"), select: false)
        home.tabManager.setPlace(pinned, to: .pinned)
        let folder = home.tabManager.newFolder()
        home.tabManager.renameFolder(folder, to: "Projets")
        home.tabManager.move(pinned, to: .pinned(folder: folder, index: 0))
        let favorite = home.tabManager.newTab(url: URL(string: "about:blank#favori"), select: false)
        home.tabManager.setPlace(favorite, to: .favorite)
        let today = work.tabManager.newTab(url: URL(string: "about:blank#jour"), select: false)
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
        #expect(second.session.spaces.last?.tabManager.todayTabs.map(\.url) == [today.url])
        #expect(second.defaults.string(forKey: BrowserSettings.Key.searchEngine) == "duckDuckGo")

        // Puis dans l'autre sens, sans rien renvoyer en écho.
        #expect(try await second.engine.sync()?.sent == 0)
        second.session.renameSpace(mirror, to: "Chez moi")
        try await second.engine.sync()
        try await first.engine.sync()
        #expect(home.record.name == "Chez moi")
        #expect(try await first.engine.sync()?.sent == 0)
    }
}
