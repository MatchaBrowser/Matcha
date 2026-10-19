import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Matcha data as seen by sync (task 7.4): snapshot, and received changes applied to the session.
@MainActor
struct MatchaSyncStoreTests {
    private let session: BrowserSession
    private let defaults: UserDefaults
    private let store: MatchaSyncStore
    private let home: SpaceSession

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        defaults = try #require(UserDefaults(suiteName: "MatchaSyncStoreTests-\(UUID().uuidString)"))
        store = MatchaSyncStore(session: session, defaults: defaults)
        home = try #require(session.spaces.first)
        session.showFavorites(in: home)
    }

    private var profileID: UUID? {
        home.record.profile?.id
    }

    private func pinnedTab(_ url: String, order: Int = 0, folder: UUID? = nil, in space: UUID? = nil) -> SyncFields {
        .tab(SyncTabFields(place: .pinned, url: URL(string: url), title: url, order: order, spaceId: space ?? home.id, folderId: folder))
    }

    @Test func `the first launch is recognized, then the snapshot follows the data`() {
        #expect(store.hasOnlyFirstLaunchData)
        let snapshot = store.snapshot()
        #expect(snapshot.count == 2)
        #expect(snapshot[home.id] == .space(SyncSpaceFields(
            name: home.record.name,
            symbol: home.record.symbol,
            theme: nil,
            order: 0,
            profileId: profileID,
        )))

        let tab = home.tabManager.newTab(url: URL(string: "about:blank#epingle"), select: false)
        home.tabManager.setPlace(tab, to: .pinned)
        let favorite = home.tabManager.newTab(url: URL(string: "about:blank#favori"), select: false)
        home.tabManager.setPlace(favorite, to: .favorite)
        defaults.set("bing", forKey: BrowserSettings.Key.searchEngine)
        session.siteZooms.setLevel(1.25, forSite: "example.com")
        home.saveNow()

        #expect(!store.hasOnlyFirstLaunchData)
        let after = store.snapshot()
        guard case let .tab(pinned) = after[tab.id], case let .tab(favored) = after[favorite.id] else {
            Issue.record("Onglets absents de l'instantané")
            return
        }
        #expect(pinned.place == .pinned && pinned.spaceId == home.id && pinned.url == tab.pinnedURL)
        #expect(favored.place == .favorite && favored.profileId == profileID && favored.spaceId == nil)
        #expect(after[SyncIdentifier.setting("searchEngine")] == .setting(SyncSettingFields(key: "searchEngine", value: .string("bing"))))
        #expect(after[SyncIdentifier.siteZoom("example.com")] == .siteZoom(SyncSiteZoomFields(site: "example.com", level: 1.25)))
    }

    @Test func `a received Space opens with its folders and tabs, without echo`() throws {
        let space = UUID()
        let folder = UUID()
        let inFolder = UUID()
        let today = UUID()
        let changes: [SyncLocalChange] = [
            .upsert(space, .space(SyncSpaceFields(name: "Travail", symbol: "briefcase.fill", theme: nil, order: 1, profileId: profileID))),
            .upsert(folder, .folder(SyncFolderFields(name: "Projets", order: 0, isCollapsed: false, spaceId: space))),
            .upsert(inFolder, pinnedTab("https://example.com/projet", folder: folder, in: space)),
            .upsert(today, .tab(SyncTabFields(
                place: .today,
                url: URL(string: "https://example.com/jour"),
                title: "Jour",
                order: 0,
                spaceId: space,
                lastActivity: SyncCoding.date(milliseconds: 1_800_000_000_000),
            ))),
        ]
        #expect(store.apply(SyncLocalChange.ordered(changes)).isEmpty)

        let opened = try #require(session.spaces.first { $0.id == space })
        #expect(session.spaces.map(\.id) == [home.id, space])
        #expect(opened.tabManager.layout.folderEntries.map(\.name) == ["Projets"])
        #expect(opened.tabManager.layout.positions[inFolder]?.folderID == folder)
        #expect(opened.tabManager.todayTabs.map(\.id) == [today])
        // Nothing loaded or selected.
        #expect(opened.tabManager.selectedTab == nil)
        #expect(opened.tabManager.tabs.allSatisfy { !$0.isLoaded })
        // The snapshot gives back what was received: nothing will be sent again.
        let snapshot = store.snapshot()
        for change in changes {
            if case let .upsert(id, fields) = change {
                #expect(snapshot[id] == fields)
            }
        }
    }

    @Test func `a change waits for its missing parent`() {
        let unknownSpace = UUID()
        let tab = UUID()
        let waiting = store.apply([.upsert(tab, pinnedTab("https://example.com", in: unknownSpace))])
        #expect(waiting == [tab])
        #expect(store.snapshot()[tab] == nil)
    }

    @Test func `a background tab follows its new address, the displayed page stays`() {
        let background = home.tabManager.newTab(url: URL(string: "about:blank#fond"), select: false)
        let shown = home.tabManager.newTab(url: URL(string: "about:blank#affiche"))
        let shownURL = shown.url
        home.saveNow()
        let moved = SyncTabFields(place: .today, url: URL(string: "about:blank#ailleurs"), title: "Ailleurs", order: 0, spaceId: home.id)
        _ = store.apply([.upsert(background.id, .tab(moved)), .upsert(shown.id, .tab(moved))])
        #expect(background.url?.absoluteString == "about:blank#ailleurs")
        #expect(!background.isLoaded)
        #expect(shown.url == shownURL)
        #expect(home.tabManager.selectedTab === shown)
    }

    @Test func `deletions close tabs and Spaces, never the last Space`() {
        let shown = home.tabManager.newTab(url: URL(string: "about:blank#affiche"))
        let tab = home.tabManager.newTab(url: URL(string: "about:blank#ferme"), select: false)
        let other = session.addSpace(inProfileOf: home)
        home.saveNow()
        _ = store.apply([.delete(tab.id, .tab), .delete(other.id, .space)])
        #expect(home.tabManager.tab(withID: tab.id) == nil)
        #expect(session.spaces.map(\.id) == [home.id])

        // The displayed tab, closed elsewhere, stays there until the user closes it.
        _ = store.apply([.delete(shown.id, .tab), .delete(home.id, .space)])
        #expect(home.tabManager.selectedTab === shown)
        #expect(session.spaces.map(\.id) == [home.id])
    }

    @Test func `settings, zooms and site decisions are applied and removed`() throws {
        let setting = SyncIdentifier.setting("showsHomeButton")
        let zoom = SyncIdentifier.siteZoom("example.com")
        let origin = try #require(SiteOrigin(key: "https://meet.example.com"))
        let permission = SyncIdentifier.sitePermission(profileID: profileID, origin: origin.key, kind: "camera")
        _ = store.apply([
            .upsert(setting, .setting(SyncSettingFields(key: "showsHomeButton", value: .bool(true)))),
            .upsert(zoom, .siteZoom(SyncSiteZoomFields(site: "example.com", level: 1.5))),
            .upsert(permission, .sitePermission(SyncSitePermissionFields(
                origin: origin.key,
                kind: "camera",
                decision: "allow",
                profileId: profileID,
            ))),
        ])
        #expect(defaults.bool(forKey: "showsHomeButton"))
        #expect(session.siteZooms.level(forSite: "example.com") == 1.5)
        #expect(session.sitePermissions.decision(.camera, for: origin, profileID: profileID) == .allow)

        _ = store.apply([.delete(setting, .setting), .delete(zoom, .siteZoom), .delete(permission, .sitePermission)])
        #expect(defaults.object(forKey: "showsHomeButton") == nil)
        #expect(session.siteZooms.level(forSite: "example.com") == 1)
        #expect(session.sitePermissions.decision(.camera, for: origin, profileID: profileID) == nil)
    }
}
