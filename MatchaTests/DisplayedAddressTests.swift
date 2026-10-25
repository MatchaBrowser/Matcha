import Foundation
@testable import Matcha
import Testing
import WebKit

/// Address shown for a page (audit W4): the displayed document's, or the one the user asked for while it loads.
@MainActor
struct DisplayedAddressTests {
    private let page = URL(string: "https://example.com/")!
    private let other = URL(string: "https://accounts.example.org:81/")!

    @Test func `a load started by the page shows nothing new until its document is displayed`() {
        var address = DisplayedAddress()
        address.documentDidChange(to: page)
        address.webViewURLDidChange(to: other, isLoading: true)
        #expect(address.url == page)
        address.documentDidChange(to: other)
        #expect(address.url == other)
    }

    @Test func `a change within the page is shown at once`() {
        var address = DisplayedAddress()
        address.documentDidChange(to: page)
        let anchor = page.appending(path: "suite")
        address.webViewURLDidChange(to: anchor, isLoading: false)
        #expect(address.url == anchor)
    }

    @Test func `a load the user asked for is shown until it fails`() {
        var address = DisplayedAddress()
        address.reset(to: page)
        address.userDidRequest(other)
        #expect(address.url == other)
        #expect(address.isPending)
        address.webViewURLDidChange(to: page, isLoading: false)
        #expect(address.url == other)
        address.documentDidChange(to: page)
        #expect(address.url == page)
        #expect(!address.isPending)
    }

    @Test func `a page can't show another site's address while that site doesn't answer`() async throws {
        let manager = TabManager(websiteDataStore: .nonPersistent())
        let configuration = TestPages.configuration()
        configuration.setURLSchemeHandler(SilentPages(), forURLScheme: SilentPages.scheme)
        let tab = manager.insertTab(configuration: configuration, after: nil, select: true)
        let attacker = TestPages.url("piege", body: "<a id='l' href='\(SilentPages.scheme)://banque/connexion'>lien</a>")
        tab.load(attacker)
        try await waitUntil { tab.title == "piege" && !tab.isLoading }

        _ = try await tab.loadedWebView.evaluateJavaScript("document.getElementById('l').click(); true")
        try await waitUntil { tab.url?.scheme == SilentPages.scheme }
        #expect(tab.displayedURL == attacker)

        // Asked for by the user: shown at once.
        let typed = try #require(URL(string: "\(SilentPages.scheme)://banque/accueil"))
        tab.load(typed)
        #expect(tab.displayedURL == typed)
    }
}
