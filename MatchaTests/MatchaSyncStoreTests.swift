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
        store = MatchaSyncStore(session: session, defaults: defaults, identifiers: .testAccount)
        home = try #require(session.spaces.first)
        session.showFavorites(in: home)
    }

    private var profileID: UUID? {
        home.record.profile?.id
    }

    private func pinnedTab(_ url: String, order: Double = 0, folder: UUID? = nil, in space: UUID? = nil) -> SyncFields {
        .tab(SyncTabFields(place: .pinned, url: URL(string: url), title: url, order: order, spaceId: space ?? home.id, folderId: folder))
    }

    @Test func `the first launch is recognized, then the snapshot follows the data`() throws {
        #expect(store.hasOnlyFirstLaunchData)
        let snapshot = try store.snapshot()
        #expect(snapshot.count == 2)
        #expect(try snapshot[home.id] == .space(SyncSpaceFields(
            name: home.record.name,
            symbol: home.record.symbol,
            theme: nil,
            order: 0,
            profileId: #require(profileID),
        )))

        let tab = home.tabManager.newTab(url: URL(string: "https://example.com/epingle"), select: false)
        home.tabManager.setPlace(tab, to: .pinned)
        let favorite = home.tabManager.newTab(url: URL(string: "https://example.com/favori"), select: false)
        home.tabManager.setPlace(favorite, to: .favorite)
        defaults.set("bing", forKey: BrowserSettings.Key.searchEngine)
        session.siteZooms.setLevel(1.25, forSite: "example.com")
        home.saveNow()

        #expect(!store.hasOnlyFirstLaunchData)
        let after = try store.snapshot()
        guard case let .tab(pinned) = after[tab.id], case let .tab(favored) = after[favorite.id] else {
            Issue.record("Onglets absents de l'instantané")
            return
        }
        #expect(pinned.place == .pinned && pinned.spaceId == home.id && pinned.url == tab.pinnedURL)
        #expect(favored.place == .favorite && favored.profileId == profileID && favored.spaceId == nil)
        #expect(after[SyncIdentifiers.testAccount.setting("searchEngine")] == .setting(SyncSettingFields(
            key: "searchEngine",
            value: .string("bing"),
        )))
        #expect(after[SyncIdentifiers.testAccount.siteZoom("example.com")] == .siteZoom(SyncSiteZoomFields(
            site: "example.com",
            level: 1.25,
        )))
    }

    @Test func `a received Space opens with its folders and tabs, without echo`() throws {
        let space = UUID()
        let folder = UUID()
        let inFolder = UUID()
        let today = UUID()
        let changes: [SyncLocalChange] = try [
            .upsert(
                space,
                .space(SyncSpaceFields(
                    name: "Travail",
                    symbol: "briefcase.fill",
                    theme: nil,
                    order: 1,
                    profileId: #require(profileID),
                )),
            ),
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
        #expect(try store.apply(SyncLocalChange.ordered(changes)).isEmpty)

        let opened = try #require(session.spaces.first { $0.id == space })
        #expect(session.spaces.map(\.id) == [home.id, space])
        #expect(opened.tabManager.layout.folderEntries.map(\.name) == ["Projets"])
        #expect(opened.tabManager.layout.positions[inFolder]?.folderID == folder)
        #expect(opened.tabManager.todayTabs.map(\.id) == [today])
        // Nothing loaded or selected.
        #expect(opened.tabManager.selectedTab == nil)
        #expect(opened.tabManager.tabs.allSatisfy { !$0.isLoaded })
        // The snapshot gives back what was received: nothing will be sent again.
        let snapshot = try store.snapshot()
        for change in changes {
            if case let .upsert(id, fields) = change {
                #expect(snapshot[id] == fields)
            }
        }
    }

    @Test func `a change waits for its missing parent`() throws {
        let unknownSpace = UUID()
        let tab = UUID()
        let waiting = try store.apply([.upsert(tab, pinnedTab("https://example.com", in: unknownSpace))])
        #expect(waiting == [tab])
        #expect(try store.snapshot()[tab] == nil)
    }

    @Test func `a pinned tab that isn't a web address stays on this Mac`() throws {
        let local = home.tabManager.newTab(url: URL(string: "file:///Users/Shared/notes.html"), select: false)
        home.tabManager.setPlace(local, to: .pinned)
        let page = home.tabManager.newTab(url: URL(string: "about:blank#jour"), select: false)
        home.saveNow()
        #expect(try store.snapshot()[local.id] == nil)
        let exceptions = try store.exceptions()
        #expect(exceptions.localRecords == [local.id])
        #expect(exceptions.nonWebPages == [page.id])
        guard case let .tab(fields) = try store.snapshot()[page.id] else {
            Issue.record("Today tab missing")
            return
        }
        #expect(fields.url == nil)
    }

    @Test func `a background tab follows its new address, the displayed page stays`() throws {
        let background = home.tabManager.newTab(url: URL(string: "about:blank#fond"), select: false)
        let shown = home.tabManager.newTab(url: URL(string: "about:blank#affiche"))
        let shownURL = shown.url
        home.saveNow()
        let moved = SyncTabFields(
            place: .today,
            url: URL(string: "https://example.com/ailleurs"),
            title: "Ailleurs",
            order: 0,
            spaceId: home.id,
        )
        _ = try store.apply([.upsert(background.id, .tab(moved)), .upsert(shown.id, .tab(moved))])
        #expect(background.url?.absoluteString == "https://example.com/ailleurs")
        #expect(!background.isLoaded)
        #expect(shown.url == shownURL)
        #expect(home.tabManager.selectedTab === shown)
    }

    @Test func `deletions close tabs and Spaces; without any left, the default ones come back`() throws {
        let shown = home.tabManager.newTab(url: URL(string: "about:blank#affiche"))
        let tab = home.tabManager.newTab(url: URL(string: "about:blank#ferme"), select: false)
        let other = session.addSpace(inProfileOf: home)
        home.saveNow()
        _ = try store.apply([.delete(tab.id, .tab), .delete(other.id, .space)])
        #expect(home.tabManager.tab(withID: tab.id) == nil)
        #expect(session.spaces.map(\.id) == [home.id])

        // The displayed tab, closed elsewhere, stays there until the user closes it.
        _ = try store.apply([.delete(shown.id, .tab)])
        #expect(home.tabManager.selectedTab === shown)

        // The last Space deleted elsewhere: the first-launch one comes back under its derived identifier, the same on
        // all Macs (SYNC.md § 2.3).
        _ = try store.apply([.delete(home.id, .space)])
        #expect(session.spaces.map(\.id) == [SyncIdentifiers.testAccount.defaultSpace])
        let profile = try #require(profileID)
        _ = try store.apply([.delete(profile, .profile)])
        #expect(session.profiles.map(\.id) == [SyncIdentifiers.testAccount.defaultProfile])
        #expect(session.spaces.count == 1)
    }

    @Test func `a deleted folder sends its content back to the root`() throws {
        let folder = UUID()
        let inFolder = UUID()
        _ = try store.apply(SyncLocalChange.ordered([
            .upsert(folder, .folder(SyncFolderFields(name: "Projets", order: 0, isCollapsed: false, spaceId: home.id))),
            .upsert(inFolder, pinnedTab("https://example.com/projet", folder: folder)),
        ]))
        _ = try store.apply([.delete(folder, .folder)])
        guard case let .tab(fields) = try store.snapshot()[inFolder] else {
            Issue.record("Pinned tab deleted with its folder")
            return
        }
        #expect(fields.folderId == nil)
    }

    @Test func `settings, zooms and site decisions are applied and removed`() throws {
        let setting = SyncIdentifiers.testAccount.setting("showsHomeButton")
        let zoom = SyncIdentifiers.testAccount.siteZoom("example.com")
        let origin = try #require(SiteOrigin(key: "https://meet.example.com"))
        let profile = try #require(profileID)
        let permission = SyncIdentifiers.testAccount.sitePermission(profileID: profile, origin: origin.key, kind: "camera")
        _ = try store.apply([
            .upsert(setting, .setting(SyncSettingFields(key: "showsHomeButton", value: .bool(true)))),
            .upsert(zoom, .siteZoom(SyncSiteZoomFields(site: "example.com", level: 1.5))),
            .upsert(permission, .sitePermission(SyncSitePermissionFields(
                origin: origin.key,
                kind: "camera",
                decision: "allow",
                profileId: profile,
            ))),
        ])
        #expect(defaults.bool(forKey: "showsHomeButton"))
        #expect(session.siteZooms.level(forSite: "example.com") == 1.5)
        // A received authorization opens nothing: this Mac keeps asking (SYNC.md § 2.6).
        #expect(session.sitePermissions.decision(.camera, for: origin, profileID: profile) == nil)

        _ = try store.apply([.delete(setting, .setting), .delete(zoom, .siteZoom)])
        #expect(defaults.object(forKey: "showsHomeButton") == nil)
        #expect(session.siteZooms.level(forSite: "example.com") == 1)
    }

    @Test func `only refusals of sites apply`() throws {
        let origin = try #require(SiteOrigin(key: "https://meet.example.com"))
        let profile = try #require(profileID)
        let permission = SyncIdentifiers.testAccount.sitePermission(profileID: profile, origin: origin.key, kind: "camera")
        let fields = { (decision: String) in
            SyncFields.sitePermission(SyncSitePermissionFields(origin: origin.key, kind: "camera", decision: decision, profileId: profile))
        }
        // An authorization of this Mac, replaced by a refusal received: a refusal.
        session.sitePermissions.set(.allow, for: .camera, origin: origin, profileID: profile)
        _ = try store.apply([.upsert(permission, fields("deny"))])
        #expect(session.sitePermissions.decision(.camera, for: origin, profileID: profile) == .deny)
        // A received authorization doesn't lift it, nor does a deletion.
        _ = try store.apply([.upsert(permission, fields("allow"))])
        _ = try store.apply([.delete(permission, .sitePermission)])
        #expect(session.sitePermissions.decision(.camera, for: origin, profileID: profile) == .deny)
        // The deletion of an authorization removes it here.
        session.sitePermissions.set(.allow, for: .camera, origin: origin, profileID: profile)
        _ = try store.apply([.delete(permission, .sitePermission)])
        #expect(session.sitePermissions.decision(.camera, for: origin, profileID: profile) == nil)
    }
}
