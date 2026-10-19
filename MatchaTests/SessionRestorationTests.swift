import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

@MainActor
struct SessionRestorationTests {
    /// Tab that went through two local pages: “un” then “deux”, back available.
    private func tabWithHistory() async throws -> BrowserTab {
        let tab = BrowserTab(configuration: TestPages.configuration())
        tab.load(TestPages.url("un"))
        try await waitUntil { tab.title == "un" && !tab.isLoading }
        tab.load(TestPages.url("deux"))
        try await waitUntil { tab.title == "deux" && tab.canGoBack && !tab.isLoading }
        return tab
    }

    @Test func `restored tab gets its page and history back`() async throws {
        let original = try await tabWithHistory()
        original.captureInteractionState()
        let state = try #require(original.savedInteractionState)

        let stored = StoredTab(id: UUID(), url: original.url, title: original.title, lastActivity: .now, interactionState: state)
        let restored = BrowserTab(restoring: stored, configuration: TestPages.configuration())
        #expect(!restored.isLoaded)
        restored.makeWebViewIfNeeded()
        try await waitUntil { restored.title == "deux" && restored.canGoBack }

        restored.goBack()
        try await waitUntil { restored.title == "un" && restored.canGoForward }
    }

    @Test func `returning to the pinned address forgets the history`() async throws {
        let tab = try await tabWithHistory()
        tab.captureInteractionState()
        tab.unload(resettingTo: TestPages.url("origine"), title: "origine")
        #expect(tab.savedInteractionState == nil)
        tab.makeWebViewIfNeeded()
        try await waitUntil { tab.title == "origine" && !tab.isLoading }
        #expect(!tab.canGoBack)
    }

    @Test func `a tab leaving the screen keeps its state`() async throws {
        let manager = TabManager(websiteDataStore: .nonPersistent())
        let first = manager.newTab(url: URL(string: "about:blank#un"))
        try await waitUntil { first.url != nil && !first.isLoading }
        first.savedInteractionState = nil
        manager.newTab()
        #expect(first.savedInteractionState != nil)
    }

    @Test func `back button works on tabs restored after relaunch`() async throws {
        let container = try BrowserSchema.makeContainer(inMemory: true)
        let first = try BrowserSession(container: container)
        let manager = try #require(first.spaces.first?.tabManager)
        let tab = manager.newTab(url: URL(string: "about:blank#a"))
        try await waitUntil { tab.url != nil && !tab.isLoading }
        try tab.load(#require(URL(string: "about:blank#b")))
        try await waitUntil { tab.canGoBack }
        let firstURL = try #require(tab.webView?.backForwardList.backItem?.url)
        first.saveAll()

        let second = try BrowserSession(container: container)
        let restoredManager = try #require(second.spaces.first?.tabManager)
        restoredManager.loadSelectedTab()
        let restored = try #require(restoredManager.selectedTab)
        try await waitUntil { restored.canGoBack }
        restored.goBack()
        try await waitUntil { restored.url == firstURL }
    }
}
