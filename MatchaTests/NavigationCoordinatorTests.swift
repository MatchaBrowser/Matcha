import Foundation
@testable import Matcha
import Testing
import WebKit

/// Integration tests with real web views and the local pages of `TestPages`.
@MainActor
struct NavigationCoordinatorTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Tab loaded with a local page containing `body`, followed by another empty tab.
    private func openPage(body: String) async throws -> (page: BrowserTab, other: BrowserTab) {
        // New tabs go on top: open the one that must come second first.
        let other = manager.newTab()
        let page = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        page.load(TestPages.url("ouvrant", body: body))
        try await waitUntil { page.title == "ouvrant" && !page.isLoading }
        return (page, other)
    }

    @Test func `tabs get the coordinator as delegates`() {
        let tab = manager.newTab()
        #expect(tab.loadedWebView.navigationDelegate === manager.coordinator)
        #expect(tab.loadedWebView.uiDelegate === manager.coordinator)
    }

    @Test func `target blank link opens a selected tab after its opener`() async throws {
        let popupURL = TestPages.url("popup")
        let (page, other) = try await openPage(body: "<a id='l' href='\(popupURL.absoluteString)' target='_blank'>lien</a>")

        _ = try await page.loadedWebView.evaluateJavaScript("document.getElementById('l').click(); true")
        try await waitUntil { manager.tabs.count == 3 }

        let popup = manager.tabs[1]
        #expect(manager.tabs[0] === page && manager.tabs[2] === other)
        #expect(manager.selectedTab === popup)
        #expect(popup.openerID == page.id)
        try await waitUntil { popup.title == "popup" && !popup.isLoading }
    }

    @Test func `window open keeps the opener`() async throws {
        let (page, _) = try await openPage(body: "")

        _ = try await page.loadedWebView.evaluateJavaScript("window.open('\(TestPages.url("popup").absoluteString)'); true")
        try await waitUntil { manager.tabs.count == 3 }
        let popup = manager.tabs[1]
        try await waitUntil { popup.title == "popup" && !popup.isLoading }

        // Without the configuration provided by WebKit, the opened window would lose its link to the page.
        let hasOpener = try await popup.loadedWebView.evaluateJavaScript("window.opener !== null")
        #expect(hasOpener as? Bool == true)
    }

    @Test func `window close from the page closes its tab`() async throws {
        let (page, other) = try await openPage(body: "")

        _ = try await page.loadedWebView.evaluateJavaScript("window.open('about:blank'); true")
        try await waitUntil { manager.tabs.count == 3 }
        let popup = manager.tabs[1]

        _ = try await popup.loadedWebView.evaluateJavaScript("window.close(); true")
        try await waitUntil { manager.tabs.count == 2 }
        #expect(manager.tabs.map(\.id) == [page.id, other.id])
    }

    @Test func `foreign scheme link is handed to another app`() async throws {
        var opened: [URL] = []
        manager.coordinator.openExternally = { opened.append($0)
            return true
        }
        let (page, _) = try await openPage(body: "<a id='l' href='mailto:moi@example.com'>courriel</a>")

        _ = try await page.loadedWebView.evaluateJavaScript("document.getElementById('l').click(); true")
        try await waitUntil { !opened.isEmpty }
        #expect(try opened == [#require(URL(string: "mailto:moi@example.com"))])
        #expect(page.url == TestPages.url("ouvrant", body: "<a id='l' href='mailto:moi@example.com'>courriel</a>"))
        #expect(manager.tabs.count == 2)
    }

    @Test func `command click opens background tabs in click order`() async throws {
        let (page, other) = try await openPage(body: "")
        let first = TestPages.url("un")
        let second = TestPages.url("deux")
        let recorder = PolicyRecorder()

        // A synthetic click in JavaScript does not carry ⌘: call the delegate directly.
        for url in [first, second] {
            let action = FakeNavigationAction(url: url, modifierFlags: .command)
            manager.coordinator.webView(page.loadedWebView, decidePolicyFor: action, decisionHandler: recorder.record)
        }

        #expect(recorder.policies == [.cancel, .cancel])
        #expect(manager.selectedTab === page)
        #expect(manager.tabs.count == 4)
        #expect(manager.tabs[0] === page && manager.tabs[3] === other)
        let (tab1, tab2) = (manager.tabs[1], manager.tabs[2])
        try await waitUntil { tab1.title == "un" && tab2.title == "deux" }
        #expect(tab1.openerID == page.id && tab2.openerID == page.id)
    }

    @Test func `middle click opens a background tab after the page`() async throws {
        let (page, other) = try await openPage(body: "")
        let recorder = PolicyRecorder()

        // Wheel click: WebKit gives a button mask, 4 for the middle button (2 is the right button).
        let action = FakeNavigationAction(url: TestPages.url("milieu"), modifierFlags: [], buttonNumber: 4)
        manager.coordinator.webView(page.loadedWebView, decidePolicyFor: action, decisionHandler: recorder.record)

        #expect(recorder.policies == [.cancel])
        #expect(manager.selectedTab === page)
        #expect(manager.tabs.count == 3)
        #expect(manager.tabs[0] === page && manager.tabs[2] === other)
        #expect(manager.tabs[1].openerID == page.id)
    }

    @Test func `right click is allowed`() throws {
        let tab = manager.newTab()
        let recorder = PolicyRecorder()
        let action = try FakeNavigationAction(url: #require(URL(string: "https://example.com/")), modifierFlags: [], buttonNumber: 2)
        manager.coordinator.webView(tab.loadedWebView, decidePolicyFor: action, decisionHandler: recorder.record)
        #expect(recorder.policies == [.allow])
        #expect(manager.tabs.count == 1)
    }

    @Test func `plain click is allowed`() throws {
        let tab = manager.newTab()
        let recorder = PolicyRecorder()
        let action = try FakeNavigationAction(url: #require(URL(string: "https://example.com/")), modifierFlags: [])
        manager.coordinator.webView(tab.loadedWebView, decidePolicyFor: action, decisionHandler: recorder.record)
        #expect(recorder.policies == [.allow])
        #expect(manager.tabs.count == 1)
    }
}
