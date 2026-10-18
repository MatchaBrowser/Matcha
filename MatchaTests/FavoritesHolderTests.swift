import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Favoris d'un profil tenus par un seul Space à la fois (`BrowserSession+Favorites`) : un Space resté en arrière-plan
/// n'écrase plus à son enregistrement les favoris ajoutés ailleurs.
@MainActor
struct FavoritesHolderTests {
    private let session: BrowserSession
    private let first: SpaceSession
    private let second: SpaceSession

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        first = try #require(session.spaces.first)
        second = session.addSpace(inProfileOf: first)
        session.showFavorites(in: first)
    }

    private func favoriteRecords() throws -> [TabRecord] {
        try session.container.mainContext.fetch(FetchDescriptor<TabRecord>()).filter { $0.place == .favorite }
    }

    private func addFavorite(in space: SpaceSession) -> BrowserTab {
        let tab = space.tabManager.newTab(url: URL(string: "about:blank#favori"), select: false)
        space.tabManager.setPlace(tab, to: .favorite)
        return tab
    }

    @Test func `a favorite added in the shown Space survives saving every Space`() throws {
        let favorite = addFavorite(in: first)
        session.saveAll()
        #expect(try favoriteRecords().map(\.id) == [favorite.id])
        // Le Space en arrière-plan s'enregistre encore seul : il ne touche pas aux favoris.
        second.saveNow()
        #expect(try favoriteRecords().map(\.id) == [favorite.id])
    }

    @Test func `a Space shown later takes the favorites over, even after another profile`() throws {
        let favorite = addFavorite(in: first)
        let other = session.addProfile(named: "Travail")
        session.showFavorites(in: other)
        session.showFavorites(in: second)
        #expect(second.tabManager.favoriteTabs.map(\.id) == [favorite.id])
        #expect(session.holdsFavorites(second))
        #expect(!session.holdsFavorites(first))
        // Retiré depuis le Space qui les tient : le premier Space, resté en arrière-plan, ne le remet pas.
        second.tabManager.delete(favorite)
        session.saveAll()
        #expect(try favoriteRecords().isEmpty)
    }

    @Test func `deleting the Space that holds the favorites hands them over`() throws {
        let favorite = addFavorite(in: first)
        session.deleteSpace(first)
        #expect(session.holdsFavorites(second))
        #expect(second.tabManager.favoriteTabs.map(\.id) == [favorite.id])
        session.saveAll()
        #expect(try favoriteRecords().map(\.id) == [favorite.id])
    }
}
