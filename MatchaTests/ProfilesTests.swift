import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

@MainActor
struct ProfilesTests {
    private let session: BrowserSession
    private let model: WindowModel

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        model = WindowModel(session: session, defaults: nil)
    }

    private var firstProfile: ProfileRecord {
        session.profiles[0]
    }

    @Test func `each profile has its own data store`() {
        let otherSpace = session.addProfile(named: "Travail")
        let other = session.profiles[1]
        let store = session.dataStore(for: firstProfile)
        #expect(session.dataStore(for: firstProfile) === store)
        #expect(session.dataStore(for: firstProfile) !== session.dataStore(for: other))
        #expect(otherSpace.record.profile?.id == other.id)
        // The tests write nothing: non-persistent stores.
        #expect(!session.dataStore(for: other).isPersistent)
        #expect(session.allDataStores().count == 2)
    }

    @Test func `tabs of a space use the data store of its profile`() {
        let space = session.addProfile(named: "Travail")
        let tab = space.tabManager.newTab()
        let store = session.dataStore(for: space.record.profile)
        #expect(tab.makeWebViewIfNeeded().configuration.websiteDataStore === store)
        #expect(session.spaces[0].tabManager.websiteDataStore !== store)
    }

    @Test func `new profile gets a default name and its first space`() {
        session.addProfile(named: "  ")
        #expect(session.profiles.map(\.name) == [String(localized: "Personal"), String(localized: "Profile \(2)")])
        #expect(session.spaces(of: session.profiles[1]).count == 1)
    }

    @Test func `deleting a profile removes its spaces but never the last profile`() async throws {
        let space = session.addProfile(named: "Travail")
        let profile = session.profiles[1]
        let favorite = space.tabManager.newTab()
        space.tabManager.setPlace(favorite, to: .favorite)
        space.saveNow()

        await session.deleteProfile(profile)
        #expect(session.profiles.count == 1)
        #expect(session.spaces.count == 1)
        let context = session.container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<ProfileRecord>()) == 1)
        #expect(try context.fetch(FetchDescriptor<TabRecord>()).allSatisfy { $0.id != favorite.id })

        await session.deleteProfile(firstProfile)
        #expect(session.profiles.count == 1)
    }

    /// Audit R1: the second profile's Space deleted, then the first profile, which held the last Space: the window
    /// used to crash on `spaces[0]`.
    @Test func `deleting the profile of the last space leaves a space to show`() async throws {
        let workSpace = session.addProfile(named: "Travail")
        let work = session.profiles[1]
        session.deleteSpace(workSpace)
        #expect(session.spaces(of: work).isEmpty)
        #expect(session.spaces.count == 1)

        await session.deleteProfile(firstProfile)
        #expect(session.profiles.map(\.id) == [work.id])
        #expect(session.spaces.count == 1)
        #expect(session.spaces.first?.record.profile?.id == work.id)
        #expect(session.spaces.first?.record.name == BrowserSession.defaultSpaceName)
        #expect(model.space === session.spaces.first)
        let context = session.container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<SpaceRecord>()) == 1)
    }

    @Test func `profiles can be renamed`() {
        session.renameProfile(firstProfile, to: " Maison ")
        session.renameProfile(firstProfile, to: "")
        #expect(firstProfile.name == "Maison")
    }

    @Test func `moving a tab within the profile keeps its page`() {
        let source = model.space
        let tab = source.tabManager.newTab()
        let target = session.addSpace(inProfileOf: source)
        let webView = tab.webView

        model.move(tab, to: target)
        #expect(source.tabManager.tab(withID: tab.id) == nil)
        #expect(target.tabManager.todayTabs.first === tab)
        #expect(tab.webView === webView)
        #expect(tab.webView?.navigationDelegate === target.tabManager.coordinator)
    }

    @Test func `moving a tab to another profile recreates it there`() async throws {
        let source = model.space
        let tab = source.tabManager.newTab(url: URL(string: "about:blank#profil"))
        try await waitUntil { tab.url != nil && !tab.isLoading }
        let target = session.addProfile(named: "Travail")
        let original = tab.url

        model.move(tab, to: target)
        #expect(source.tabManager.tab(withID: tab.id) == nil)
        let moved = try #require(target.tabManager.todayTabs.first)
        #expect(moved !== tab)
        #expect(moved.makeWebViewIfNeeded().configuration.websiteDataStore === session.dataStore(for: target.record.profile))
        // Recreated from the original address (WebKit writes it “about:blank%23profil”).
        try await waitUntil { moved.url == original && !moved.isLoading }
    }
}
