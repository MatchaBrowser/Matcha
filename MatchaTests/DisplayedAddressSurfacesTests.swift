import AppKit
import Foundation
@testable import Matcha
import Testing
import WebKit

/// Review TR1: what is shown, copied or acted upon reads the displayed document, never the load a page started. The
/// scenario of audit W4: a page sends the tab to a site that never answers; its own content stays on screen.
@MainActor
struct DisplayedAddressSurfacesTests {
    private let session: BrowserSession
    private let window: WindowModel
    private let settings = CommandBarSettings(searchEngine: .google, newTabPage: .blank, homePage: "", showsSearchSuggestions: false)
    private let attacker = TestPages.url("trap", body: "<a id='l' href='\(SilentPages.scheme)://bank/login'>link</a>")

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        window = WindowModel(session: session, defaults: nil)
        window.windowDidAppear()
    }

    /// A tab of the window left on the attacker's page while a load to the silent bank is pending.
    private func pendingTab(select: Bool = true) async throws -> BrowserTab {
        let configuration = TestPages.configuration()
        configuration.setURLSchemeHandler(SilentPages(), forURLScheme: SilentPages.scheme)
        let tab = window.tabManager.insertTab(configuration: configuration, after: nil, select: select)
        tab.load(attacker)
        try await waitUntil { tab.title == "trap" && !tab.isLoading }
        _ = try await tab.loadedWebView.evaluateJavaScript("document.getElementById('l').click(); true")
        try await waitUntil { tab.url?.host() == "bank" }
        return tab
    }

    @Test func `the tab shows and acts on the page on screen`() async throws {
        let tab = try await pendingTab()
        #expect(tab.displayedURL == attacker)
        #expect(tab.documentURL == attacker)
        // Without a title, the host of the page on screen, not the bank's.
        _ = try await tab.loadedWebView.evaluateJavaScript("document.title = ''; true")
        try await waitUntil { tab.title?.isEmpty == true }
        #expect(tab.displayTitle == attacker.host())
        #expect(PopupWindowView.windowTitle(of: tab) == attacker.host())
    }

    @Test func `the address bar and the copied address are the page's on screen`() async throws {
        let tab = try await pendingTab()
        let bar = CommandBarModel(windowModel: window, suggestions: FakeSuggestionEngine().provider())
        bar.editCurrentTab(settings)
        #expect(bar.text == attacker.absoluteString)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("DisplayedAddressSurfacesTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(window.copySelectedTabURL(to: pasteboard))
        #expect(pasteboard.string(forType: .string) == attacker.absoluteString)
        #expect(tab.url?.host() == "bank")
    }

    @Test func `the command bar lists the tab under the address on screen`() async throws {
        let tab = try await pendingTab(select: false)
        window.tabManager.newTab()
        let listed = OpenTabsProvider(windowModel: window).openTabs().first { $0.id == "tab:\(tab.id.uuidString)" }
        #expect(listed?.url == attacker)
    }

    @Test func `a sign-in window has no title before it shows a document`() {
        #expect(PopupWindowView.windowTitle(of: BrowserTab(configuration: WKWebViewConfiguration())).isEmpty)
    }
}
