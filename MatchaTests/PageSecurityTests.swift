import Foundation
@testable import Matcha
import Testing
import WebKit

/// Security shown next to the address (audit W5): padlock and certificate for https, “Not Secure” for http.
@MainActor
struct PageSecurityTests {
    @Test(arguments: [
        ("https://example.com/", true, PageSecurity.secure),
        ("https://example.com/", false, .partlySecure),
        ("http://example.com/", true, .notSecure),
        ("http://[::1]:3000/", true, .notSecure),
        ("file:///Users/moi/page.html", true, .none),
        ("about:blank", true, .none),
        ("data:text/html,salut", true, .none),
        ("matcha-source:https://example.com/", true, .none),
    ])
    func `security follows the scheme and the page's content`(url: String, onlySecure: Bool, security: PageSecurity) {
        #expect(PageSecurity.of(URL(string: url), hasOnlySecureContent: onlySecure) == security)
        #expect(PageSecurity.of(nil, hasOnlySecureContent: true) == .none)
    }

    @Test func `only an encrypted page has a certificate to show`() {
        #expect(PageSecurity.secure.hasCertificate)
        #expect(PageSecurity.partlySecure.hasCertificate)
        #expect(!PageSecurity.notSecure.hasCertificate)
        #expect(!PageSecurity.none.hasCertificate)
    }

    @Test func `a tab shows nothing it doesn't know`() {
        let manager = TabManager(websiteDataStore: .nonPersistent())
        let stored = StoredTab(id: UUID(), url: URL(string: "https://example.com/"), lastActivity: .now)
        let restored = BrowserTab(restoring: stored, configuration: TestPages.configuration())
        // Not loaded: nothing is known about its connection.
        #expect(restored.security == .none)

        // Loading what the user asked for: the shown address isn't the displayed page's yet.
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url("lent"))
        #expect(tab.security == .none)
    }

    @Test func `an http page is not secure`() async throws {
        let manager = TabManager(websiteDataStore: .nonPersistent())
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        let page = try #require(URL(string: "http://example.com/"))
        tab.loadedWebView.loadSimulatedRequest(URLRequest(url: page), responseHTML: "<title>http</title>")
        try await waitUntil { tab.displayedURL == page && !tab.isLoading }
        #expect(tab.security == .notSecure)
        #expect(tab.serverTrust == nil)
    }

    @Test func `http addresses are tried in https first`() {
        let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent())
        #expect(configuration.defaultWebpagePreferences.preferredHTTPSNavigationPolicy == .automaticFallbackToHTTP)
    }
}
