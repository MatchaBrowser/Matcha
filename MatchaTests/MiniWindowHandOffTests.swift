import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

@MainActor
struct MiniWindowHandOffTests {
    private let session: BrowserSession

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
    }

    /// Page of a mini window on the profile of `space`, loaded on `pages`, one after the other.
    private func miniTab(in space: SpaceSession, pages: [String]) async throws -> BrowserTab {
        let configuration = TestPages.configuration()
        configuration.websiteDataStore = session.dataStore(for: space.record.profile)
        let tab = BrowserTab(configuration: configuration)
        for name in pages {
            tab.load(TestPages.url(name))
            try await waitUntil { tab.title == name && !tab.isLoading }
        }
        return tab
    }

    @Test func `same profile keeps the live page and its history`() async throws {
        let space = session.spaces[0]
        let existing = space.tabManager.newTab()
        let tab = try await miniTab(in: space, pages: ["un", "deux"])
        let webView = tab.webView

        let moved = MiniWindowHandOff.move(tab, profileID: space.record.profile?.id, to: space)
        #expect(moved === tab)
        #expect(tab.webView === webView)
        #expect(space.tabManager.todayTabs.map(\.id) == [tab.id, existing.id])
        #expect(space.tabManager.selectedTab === tab)
        #expect(tab.webView?.navigationDelegate === space.tabManager.coordinator)
        #expect(tab.canGoBack)
        #expect(tab.title == "deux")
    }

    @Test func `another profile reloads the address there and frees the mini page`() async throws {
        let space = session.spaces[0]
        let other = session.addProfile(named: "Travail")
        let tab = BrowserTab(configuration: WebConfigurationFactory
            .makeConfiguration(websiteDataStore: session.dataStore(for: space.record.profile)))
        // Address that the web view of the new profile can load (not the test scheme).
        let url = blankPage("travail")
        tab.load(url)
        try await waitUntil { tab.url == url && !tab.isLoading }

        let moved = try #require(MiniWindowHandOff.move(tab, profileID: space.record.profile?.id, to: other))
        #expect(moved !== tab)
        #expect(tab.webView == nil)
        #expect(other.tabManager.selectedTab === moved)
        #expect(moved.makeWebViewIfNeeded().configuration.websiteDataStore === session.dataStore(for: other.record.profile))
        try await waitUntil { moved.url == url && !moved.isLoading }
    }

    @Test func `a mini window without a page moves nothing`() {
        let space = session.spaces[0]
        let tab = BrowserTab(configuration: WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent()))
        #expect(MiniWindowHandOff.move(tab, profileID: space.record.profile?.id, to: space) == nil)
        #expect(space.tabManager.tabs.isEmpty)
    }
}
