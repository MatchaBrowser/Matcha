import AppKit
import Foundation
@testable import Matcha
import Testing
import WebKit

/// Sign-in windows (task 5.8) in a session: Spaces, mini windows, private window, profiles. Real web views, pages from
/// `TestPages`, windows never shown, closed at the end of each test (`PopupWindowTests`).
@MainActor
@Suite(.serialized)
final class PopupWindowSessionTests {
    private let session: BrowserSession
    private let model: WindowModel

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true), services: .withPopupWindows())
        model = WindowModel(session: session, defaults: nil)
        session.popupManager.prepareForTests()
    }

    isolated deinit {
        session.popupManager.closeAll()
    }

    private var popups: PopupWindowManager {
        session.popupManager
    }

    /// Selected tab of the Space `space` on the local page `name`, once loaded.
    private func openTab(
        _ name: String,
        in space: SpaceSession,
        dataStore: WKWebsiteDataStore = .nonPersistent(),
    ) async throws -> BrowserTab {
        let configuration = WebConfigurationFactory().makeConfiguration(websiteDataStore: dataStore)
        configuration.setURLSchemeHandler(TestPages(), forURLScheme: TestPages.scheme)
        let tab = space.tabManager.insertTab(configuration: configuration, after: nil, select: true)
        tab.load(TestPages.url(name))
        try await waitUntil { tab.title == name && !tab.isLoading }
        return tab
    }

    /// Sign-in window opened by `tab` of the Space `space`, through the delegate as WebKit does.
    @discardableResult
    private func openPopup(from tab: BrowserTab, in space: SpaceSession) throws -> PopupWindowController {
        let webView = try #require(space.tabManager.coordinator.webView(
            tab.loadedWebView,
            createWebViewWith: tab.configuration,
            for: FakeNavigationAction(url: TestPages.url("connexion"), modifierFlags: []),
            windowFeatures: FakeWindowFeatures(width: 500, height: 600),
        ))
        return try #require(popups.window(for: webView))
    }

    @Test func `every Space opens its sign-in windows in the session`() {
        let added = session.addSpace(in: session.spaces[0].record.profile)
        #expect(session.spaces.allSatisfy { $0.tabManager.popupWindows === session.popupWindows })
        #expect(added.tabManager.popupWindows === session.popupWindows)
        #expect(!popups.isPrivate)
        #expect(popups.downloadScope == .regular)
    }

    /// Permissions and history: those of the profile and the Space of the originating page.
    @Test func `a sign-in window uses the profile of its opener`() async throws {
        let space = model.space
        let tab = try await openTab("ouvrant", in: space)
        let popup = try openPopup(from: tab, in: space)
        let webView = try #require(popup.tab.webView)

        #expect(popups.sitePermissions(for: webView)?.profileID == space.record.profile?.id)
        #expect(popups.historyScope(for: webView)?.spaceID == space.id)
        #expect(popups.historyScope(for: webView)?.profileID == space.record.profile?.id)
        #expect(popups.isVisible(popup.tab))
    }

    @Test func `sign-in windows of a private window are private, dark, and close with it`() async throws {
        let privateSession = BrowserSession.makePrivate(services: .withPopupWindows())
        privateSession.popupManager.prepareForTests()
        let space = privateSession.spaces[0]
        let tab = try await openTab("ouvrant", in: space)

        try await tab.loadedWebView.openWindow(TestPages.url("connexion"), features: "width=500,height=600")
        try await waitUntil { privateSession.popupManager.windows.count == 1 }
        let popup = privateSession.popupManager.windows[0]
        let webView = try #require(popup.tab.webView)

        #expect(popup.window.appearance?.name == .darkAqua)
        #expect(privateSession.popupManager.historyScope(for: webView) == nil)
        #expect(privateSession.popupManager.downloadScope == privateSession.downloadScope)
        #expect(popup.tab.configuration.websiteDataStore === tab.configuration.websiteDataStore)
        #expect(popups.windows.isEmpty)

        privateSession.popupManager.closeAll()
        #expect(privateSession.popupManager.windows.isEmpty)
        #expect(!popup.tab.isLoaded)
    }

    @Test func `deleting a profile closes its sign-in windows only`() async throws {
        let work = session.addProfile(named: "Travail")
        let profile = try #require(work.record.profile)
        let kept = try await openTab("perso", in: session.spaces[0])
        let gone = try await openTab("travail", in: work, dataStore: session.dataStore(for: profile))
        let keptPopup = try openPopup(from: kept, in: session.spaces[0])
        try openPopup(from: gone, in: work)
        #expect(popups.windows.count == 2)

        await session.deleteProfile(profile)

        #expect(popups.windows.map(\.id) == [keptPopup.id])
    }

    /// From a mini window: no new mini window, and ⌘-click in the sign-in window adds a background tab to the target
    /// Space, as from the mini window.
    @Test func `a sign-in window from a mini window`() async throws {
        let miniWindows = MiniWindowManager.forTests(session: session)
        let mini = miniWindows.openNew(loading: TestPages.url("ouvrant"), source: .link)
        try await waitUntil { mini.tab.title == "ouvrant" && !mini.tab.isLoading }

        try await mini.tab.loadedWebView.openWindow(TestPages.url("connexion"), features: "width=500,height=600")
        try await waitUntil { popups.windows.count == 1 }
        let popup = popups.windows[0]
        try await waitUntil { popup.tab.title == "connexion" && !popup.tab.isLoading }

        #expect(miniWindows.windows.map(\.id) == [mini.id])
        #expect(popup.opener.host === miniWindows)
        #expect(popup.opener.page === mini.tab)
        #expect(try await popup.tab.loadedWebView.hasOpener())
        #expect(try popups.sitePermissions(for: #require(popup.tab.webView))?.profileID == mini.profileID)

        let recorder = PolicyRecorder()
        let action = FakeNavigationAction(url: TestPages.url("lien"), modifierFlags: .command)
        popups.coordinator.webView(popup.tab.loadedWebView, decidePolicyFor: action, decisionHandler: recorder.record)
        #expect(recorder.policies == [.cancel])
        #expect(session.spaces[0].tabManager.todayTabs.count == 1)
        #expect(miniWindows.windows.count == 1)
        mini.close()
    }
}
