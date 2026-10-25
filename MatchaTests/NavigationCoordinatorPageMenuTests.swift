import Foundation
@testable import Matcha
import Testing
import WebKit

/// Window opened for a context menu choice (task 5.9), by the navigation delegate of a Space's tabs, with real web
/// views and the pages of `TestPages`. The window is requested from the delegate the way WebKit does for “… in New
/// Window” (checked: `.other`, without button or key, without size).
@MainActor
@Suite(.webKit)
struct NavigationCoordinatorPageMenuTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Selected tab on a local page, at the top, followed by another empty tab.
    private func openPage() async throws -> (page: BrowserTab, other: BrowserTab) {
        let other = manager.newTab()
        let page = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        page.load(TestPages.url("ouvrant"))
        try await waitUntil { page.title == "ouvrant" && !page.isLoading }
        return (page, other)
    }

    /// Remembers the choice `destination` in the web view of `tab`, like a menu item.
    private func choose(_ destination: PageMenuDestination, in tab: BrowserTab) throws {
        let webView = try #require(tab.loadedWebView as? BrowserWebView)
        webView.pageMenuIntent.choose(destination, openingPoint: PeekLayout.center, at: .now)
    }

    private func pendingIntent(of tab: BrowserTab) -> PageMenuIntent? {
        (tab.webView as? BrowserWebView)?.pageMenuIntent.intent
    }

    /// Window that the page of `tab` requests for `url`.
    private func requestWindow(
        _ url: URL,
        from tab: BrowserTab,
        type: WKNavigationType = .other,
        features: FakeWindowFeatures = FakeWindowFeatures(),
    ) -> WKWebView? {
        manager.coordinator.webView(
            tab.loadedWebView,
            createWebViewWith: tab.loadedWebView.configuration,
            for: FakeNavigationAction(url: url, modifierFlags: [], buttonNumber: 0, navigationType: type),
            windowFeatures: features,
        )
    }

    @Test func `open in new tab adds a background tab after the page, once`() async throws {
        let (page, other) = try await openPage()
        try choose(.backgroundTab, in: page)

        let created = requestWindow(TestPages.url("cible"), from: page)

        #expect(manager.tabs.count == 3)
        #expect(manager.tabs[0] === page && manager.tabs[2] === other)
        #expect(created != nil && manager.tabs[1].webView === created)
        #expect(manager.tabs[1].openerID == page.id)
        #expect(manager.selectedTab === page)
        #expect(pendingIntent(of: page) == nil)

        // The next window comes from the page (`window.open`): a tab in the foreground, as before.
        let next = requestWindow(TestPages.url("popup"), from: page)
        #expect(manager.tabs.count == 4)
        #expect(manager.selectedTab?.webView === next)
    }

    @Test func `the choice expires after one second`() async throws {
        let (page, _) = try await openPage()
        try choose(.backgroundTab, in: page)
        manager.coordinator.now = { .now.addingTimeInterval(2) }

        let created = requestWindow(TestPages.url("popup"), from: page)

        #expect(manager.selectedTab?.webView === created)
        #expect(pendingIntent(of: page) == nil)
    }

    /// A choice made in another page does not apply to this one (real `window.open`); a `target=_blank` link never
    /// takes it.
    @Test func `page windows are never taken for a menu choice`() async throws {
        let (page, other) = try await openPage()
        try choose(.backgroundTab, in: other)

        _ = try await page.loadedWebView.evaluateJavaScript("window.open('\(TestPages.url("popup").absoluteString)'); true")
        try await waitUntil { manager.tabs.count == 3 }
        #expect(manager.selectedTab === manager.tabs[1])
        #expect(manager.tabs[1].openerID == page.id)
        #expect(pendingIntent(of: other) != nil)

        try choose(.backgroundTab, in: page)
        let blank = requestWindow(TestPages.url("blank"), from: page, type: .linkActivated)
        #expect(manager.selectedTab?.webView === blank)
        #expect(pendingIntent(of: page) != nil)
    }

    @Test func `open in new tab from Peek keeps the Peek`() async throws {
        let (page, other) = try await openPage()
        let recorder = PolicyRecorder()
        let shiftClick = FakeNavigationAction(url: TestPages.url("cible"), modifierFlags: .shift)
        manager.coordinator.webView(page.loadedWebView, decidePolicyFor: shiftClick, decisionHandler: recorder.record)
        let peek = try #require(manager.peek)
        try await waitUntil { peek.tab.title == "cible" && !peek.tab.isLoading }
        try choose(.backgroundTab, in: peek.tab)

        let created = requestWindow(TestPages.url("fond"), from: peek.tab)

        #expect(manager.tabs.count == 3)
        #expect(manager.tabs[0] === page && manager.tabs[2] === other)
        #expect(manager.tabs[1].webView === created && manager.tabs[1].openerID == page.id)
        #expect(manager.peek?.id == peek.id)
        #expect(manager.selectedTab === page)
    }

    @Test func `open in Peek opens the link in Peek`() async throws {
        let (page, _) = try await openPage()
        try choose(.peek, in: page)

        #expect(requestWindow(TestPages.url("cible"), from: page) == nil)

        let peek = try #require(manager.peek)
        #expect(peek.sourceTabID == page.id)
        #expect(peek.openingPoint == PeekLayout.center)
        try await waitUntil { peek.tab.title == "cible" && !peek.tab.isLoading }
        #expect(manager.tabs.count == 2)
        #expect(manager.selectedTab === page)
    }

    /// Peek refused (tab that is not displayed, `data:` address): a background tab rather than nothing.
    @Test func `open in Peek falls back to a background tab`() async throws {
        let (page, other) = try await openPage()
        try choose(.peek, in: other)
        // App configuration, without the scheme of the test pages: a web link (never loaded here).
        let link = try #require(URL(string: "https://example.org/cible"))
        let hidden = requestWindow(link, from: other)
        #expect(hidden != nil && manager.tabs.last?.webView === hidden)

        try choose(.peek, in: page)
        let data = try #require(URL(string: "data:text/html,<p>donn%C3%A9es</p>"))
        let created = requestWindow(data, from: page)
        #expect(created != nil && manager.tabs[1].webView === created)

        #expect(manager.peek == nil)
        #expect(manager.tabs.count == 4)
        #expect(manager.selectedTab === page)
    }

    @Test func `a link to another app opens that app`() async throws {
        let (page, _) = try await openPage()
        var opened: [URL] = []
        manager.coordinator.openExternally = { url in
            opened.append(url)
            return true
        }
        try choose(.backgroundTab, in: page)
        let mail = try #require(URL(string: "mailto:contact@example.org"))

        #expect(requestWindow(mail, from: page) == nil)
        #expect(opened == [mail])
        #expect(manager.tabs.count == 2)
    }

    /// Review WB4: from the menu, any app other than Mail or Phone waits in the banner; a file share never opens.
    @Test func `from the menu, another app asks first and a file share never opens`() async throws {
        let (page, _) = try await openPage()
        var opened: [URL] = []
        manager.coordinator.openExternally = { url in
            opened.append(url)
            return true
        }
        manager.coordinator.applicationForURL = { _ in URL(filePath: "/System/Library/CoreServices/Finder.app") }
        try choose(.backgroundTab, in: page)
        #expect(try requestWindow(#require(URL(string: "smb://attaquant/partage")), from: page) == nil)
        #expect(page.permissionPrompts.currentAction == nil)

        try choose(.backgroundTab, in: page)
        let zoom = try #require(URL(string: "zoommtg://zoom.us/join"))
        #expect(requestWindow(zoom, from: page) == nil)
        #expect(opened.isEmpty)
        #expect(page.permissionPrompts.currentAction?.action == .openApp(scheme: "zoommtg"))
        page.permissionPrompts.answerAction(.allowOnce)
        #expect(opened == [zoom])
    }

    /// Review WB21: Back in the page's menu goes through the tab, like the toolbar: it leaves a failure shown over the
    /// page first.
    @Test func `back in the menu leaves a failure shown over the page`() async throws {
        let (page, _) = try await openPage()
        let failed = try #require(URL(string: "https://absent.example/"))
        page.provisionalLoadDidFail(NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotFindHost,
            userInfo: [NSURLErrorFailingURLErrorKey: failed],
        ))
        #expect(page.displayedURL == failed)

        manager.coordinator.pageMenu(perform: .goBack, in: page.loadedWebView)
        #expect(page.loadFailure.error == nil)
        #expect(page.displayedURL == TestPages.url("ouvrant"))
    }

    /// A sign-in window (given size) is never the one for the menu: the choice still waits for its own window.
    @Test func `a sign-in window is never taken for the choice`() async throws {
        let (page, _) = try await openPage()
        let popups = PopupWindowManager.forTests()
        defer { popups.closeAll() }
        manager.popupWindows = popups
        try choose(.backgroundTab, in: page)

        _ = requestWindow(TestPages.url("connexion"), from: page, features: FakeWindowFeatures(width: 500, height: 600))

        #expect(popups.windows.count == 1)
        #expect(manager.tabs.count == 2)
        #expect(pendingIntent(of: page) != nil)
        let created = requestWindow(TestPages.url("cible"), from: page)
        #expect(manager.tabs[1].webView === created && manager.selectedTab === page)
    }

    @Test func `the menu offers Peek in tabs only`() async throws {
        let (page, other) = try await openPage()
        #expect(manager.coordinator.pageMenuOffersPeek(in: page.loadedWebView))
        #expect(manager.coordinator.pageMenuOffersPeek(in: other.loadedWebView))

        let peek = try #require(manager.openPeek(TestPages.url("cible"), from: page))
        #expect(!manager.coordinator.pageMenuOffersPeek(in: peek.tab.loadedWebView))
        #expect(!manager.coordinator.pageMenuOffersPeek(in: WKWebView()))
    }
}
