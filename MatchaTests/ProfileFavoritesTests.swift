import Foundation
@testable import Matcha
import SwiftData
import Testing

/// A profile's favorites shared by its Spaces (`ProfileFavorites`, review ON1): the same tabs in each Space, whichever
/// window changes them, saved once; two windows on two Spaces of the profile.
@MainActor
struct ProfileFavoritesTests {
    private let session: BrowserSession
    private let first: SpaceSession
    private let second: SpaceSession
    private let firstWindow: WindowModel
    private let secondWindow: WindowModel

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        first = try #require(session.spaces.first)
        second = session.addSpace(inProfileOf: first)
        firstWindow = WindowModel(session: session, defaults: nil, spaceID: first.id)
        secondWindow = WindowModel(session: session, defaults: nil, spaceID: second.id)
        firstWindow.windowDidAppear()
        secondWindow.windowDidAppear()
        // The first window is in front: the second one is changed without becoming the key window.
        firstWindow.windowDidBecomeKey()
    }

    private func records(_ id: UUID) throws -> [TabRecord] {
        try session.container.mainContext.fetch(FetchDescriptor<TabRecord>()).filter { $0.id == id }
    }

    private func favoriteRecords() throws -> [TabRecord] {
        try session.container.mainContext.fetch(FetchDescriptor<TabRecord>()).filter { $0.place == .favorite }
    }

    @discardableResult
    private func addFavorite(in space: SpaceSession, _ name: String = "favorite") -> BrowserTab {
        let tab = space.tabManager.newTab(url: URL(string: "about:blank#\(name)"), select: false)
        space.tabManager.setPlace(tab, to: .favorite)
        return tab
    }

    @Test func `a favorite added in one Space is the same tab in the others, saved once`() throws {
        let favorite = addFavorite(in: second)
        #expect(first.tabManager.favoriteTabs.map(\.id) == [favorite.id])
        #expect(first.tabManager.tab(withID: favorite.id) === favorite)
        #expect(session.savesFavorites(first) && !session.savesFavorites(second))
        session.saveAll()
        second.saveNow()
        #expect(try favoriteRecords().map(\.id) == [favorite.id])
    }

    /// ON1, case 1: the tab used to be saved by no Space, then forgotten at the next click in that window.
    @Test func `a today tab dropped into the favorites of the window behind stays a favorite`() throws {
        let tab = first.tabManager.newTab(url: URL(string: "about:blank#today"))
        let action = SidebarDropAction(tabManager: second.tabManager, windowModel: secondWindow)
        #expect(action.perform(.tab(tab.id), at: .favorites(index: 0)))
        #expect(second.tabManager.place(of: tab) == .favorite)
        #expect(first.tabManager.place(of: tab) == .favorite)
        secondWindow.windowDidBecomeKey()
        firstWindow.windowDidBecomeKey()
        #expect(second.tabManager.place(of: tab) == .favorite)
        session.saveAll()
        #expect(try records(tab.id).map(\.place) == [.favorite])
    }

    /// ON1, case 2: the favorite used to be duplicated, a favorite here and a today tab there.
    @Test func `a favorite dropped into the today tabs of the window behind moves there, once`() throws {
        let favorite = addFavorite(in: first)
        session.saveAll()
        let action = SidebarDropAction(tabManager: second.tabManager, windowModel: secondWindow)
        #expect(action.perform(.tab(favorite.id), at: .today(index: 0)))
        #expect(second.tabManager.place(of: favorite) == .today)
        #expect(first.tabManager.tab(withID: favorite.id) == nil)
        session.saveAll()
        let saved = try records(favorite.id)
        #expect(saved.map(\.place) == [.today])
        #expect(saved.first?.space?.id == second.id)
    }

    /// ON1, case 3: deleting from the window behind used to be undone.
    @Test func `a favorite deleted from the window behind is deleted everywhere`() throws {
        let favorite = addFavorite(in: first)
        session.saveAll()
        second.tabManager.delete(favorite)
        #expect(first.tabManager.tab(withID: favorite.id) == nil)
        session.saveAll()
        #expect(try favoriteRecords().isEmpty)
    }

    @Test func `a Space opened later, or after a relaunch, shares the same tabs`() throws {
        let favorite = addFavorite(in: first)
        session.saveAll()
        let third = session.addSpace(inProfileOf: first)
        #expect(third.tabManager.tab(withID: favorite.id) === favorite)

        let relaunched = try BrowserSession(container: session.container)
        let spaces = relaunched.spaces.filter { $0.openedProfileID == first.openedProfileID }
        #expect(spaces.count == 3)
        let tabs = spaces.compactMap(\.tabManager.favoriteTabs.first)
        #expect(tabs.count == 3 && tabs.allSatisfy { $0 === tabs[0] })
    }

    @Test func `the favorites' links open in the Space of the window in front`() {
        let favorite = addFavorite(in: first)
        secondWindow.windowDidBecomeKey()
        #expect(favorite.delegate === second.tabManager.coordinator)
        firstWindow.windowDidBecomeKey()
        #expect(favorite.delegate === first.tabManager.coordinator)
        // A change made in the window behind leaves them in the Space in front.
        addFavorite(in: second, "other")
        #expect(favorite.delegate === first.tabManager.coordinator)
    }

    @Test func `deleting the Space that saves the favorites hands the saving over`() throws {
        let favorite = addFavorite(in: first)
        session.deleteSpace(first)
        #expect(session.savesFavorites(second))
        #expect(second.tabManager.favoriteTabs.map(\.id) == [favorite.id])
        session.saveAll()
        #expect(try favoriteRecords().map(\.id) == [favorite.id])
    }

    /// Review ON2: one registry for the session, so one window shows the favorite, the other offers to show it.
    @Test func `two windows on two Spaces never show the same favorite at once`() {
        let favorite = addFavorite(in: first)
        first.tabManager.setSelection(favorite.id, for: firstWindow.viewer)
        second.tabManager.setSelection(favorite.id, for: secondWindow.viewer)
        #expect(second.tabManager.shows(favorite.id, in: secondWindow.viewer))
        #expect(!first.tabManager.shows(favorite.id, in: firstWindow.viewer))
    }

    /// Review ON4: the hidden Space reconciled first used to unload the favorite under the other window's eyes.
    @Test func `a favorite deleted on another Mac stays while a window shows it`() throws {
        let favorite = addFavorite(in: first)
        session.saveAll()
        second.tabManager.setSelection(favorite.id, for: secondWindow.viewer)
        try records(favorite.id).forEach(session.container.mainContext.delete)
        var changes = BrowserSession.SyncChanges()
        changes.favorites = try [#require(first.openedProfileID)]
        session.reload(after: changes)
        #expect(second.tabManager.tab(withID: favorite.id) === favorite)
        #expect(first.tabManager.tab(withID: favorite.id) === favorite)
    }

    // MARK: Tabs between windows (review TS10)

    /// A pinned tab in a folder, dropped into the other window's today tabs: the same tab leaves the folder and its Space.
    @Test func `a tab of a folder brought to the other Space leaves its folder`() throws {
        let manager = first.tabManager
        let tab = manager.newTab(url: testURL("about:blank#dossier"), select: false)
        manager.setPlace(tab, to: .pinned)
        let folder = manager.newFolder()
        manager.move(tab, to: .pinned(folder: folder, index: 0))
        #expect(manager.layout.pinned.folder(folder)?.items.map(\.id) == [tab.id])

        let brought = try #require(session.bringTab(tab.id, into: second.tabManager))
        #expect(brought === tab)
        #expect(manager.tab(withID: tab.id) == nil)
        #expect(manager.layout.pinned.folder(folder)?.items.isEmpty == true)
        #expect(second.tabManager.todayTabs.first === tab)
    }

    /// A pane of a split brought to the other Space: it leaves the split, which is undone with a single pane left.
    @Test func `a pane brought to the other Space undoes its split`() throws {
        let manager = first.tabManager
        let left = manager.newTab(url: testURL("about:blank#gauche"))
        let right = manager.newTab(url: testURL("about:blank#droite"), select: false)
        manager.select(left)
        try #require(manager.openInSplit(right))
        #expect(manager.layout.split(containing: left.id) != nil)

        _ = try #require(session.bringTab(right.id, into: second.tabManager))
        #expect(manager.layout.split(containing: left.id) == nil)
        #expect(manager.tab(withID: left.id) === left)
        #expect(second.tabManager.tab(withID: right.id) === right)
    }

    /// A tab brought to a Space of another profile is recreated there from its address; the original goes.
    @Test func `a tab brought to another profile is recreated with its address`() throws {
        let other = session.addProfile(named: "Travail")
        let tab = first.tabManager.newTab(url: testURL("about:blank#profil"), select: false)
        let brought = try #require(session.bringTab(tab.id, into: other.tabManager))
        #expect(brought !== tab)
        #expect(brought.url == tab.url)
        #expect(first.tabManager.tab(withID: tab.id) == nil)
        #expect(other.tabManager.tab(withID: brought.id) === brought)
    }
}
