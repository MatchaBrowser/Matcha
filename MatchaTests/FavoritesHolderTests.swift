import Foundation
@testable import Matcha
import SwiftData
import Testing

/// A profile's favorites held by a single Space at a time (`BrowserSession+Favorites`): a Space left in the
/// background no longer overwrites, when it saves, the favorites added elsewhere.
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
        // The background Space still saves on its own: it does not touch the favorites.
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
        // Removed from the Space that holds them: the first Space, left in the background, does not put it back.
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
