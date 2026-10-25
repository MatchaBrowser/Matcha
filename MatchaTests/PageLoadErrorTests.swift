import Foundation
@testable import Matcha
import Testing
import WebKit

/// A page that couldn't load (audit K5): why, in place of the page, with “Try Again”.
@MainActor
struct PageLoadErrorTests {
    private let url = URL(string: "https://example.com/page")!

    @Test(arguments: [
        (NSURLErrorNotConnectedToInternet, PageLoadError.Kind.offline),
        (NSURLErrorCannotFindHost, .serverNotFound),
        (NSURLErrorTimedOut, .timedOut),
        (NSURLErrorCannotConnectToHost, .cannotConnect),
        (NSURLErrorServerCertificateUntrusted, .certificate),
        (NSURLErrorServerCertificateHasBadDate, .certificate),
        (NSURLErrorUserCancelledAuthentication, .loginRequired),
        (NSURLErrorBadServerResponse, .other),
    ])
    func `errors are told apart`(code: Int, kind: PageLoadError.Kind) {
        #expect(PageLoadError(NSError(domain: NSURLErrorDomain, code: code), url: url)?.kind == kind)
    }

    @Test func `loads the app or the user stopped show nothing`() {
        #expect(PageLoadError(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled), url: url) == nil)
        #expect(PageLoadError(NSError(domain: "WebKitErrorDomain", code: 102), url: url) == nil)
        #expect(PageLoadError(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut), url: nil) == nil)
        #expect(PageLoadError(NSError(domain: "WebKitErrorDomain", code: 103), url: url)?.kind == .other)
    }

    @Test func `a first load that fails keeps its address and can be tried again`() async throws {
        let manager = TabManager(websiteDataStore: .nonPersistent())
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        // Nothing listens there: refused at once, without network.
        let refused = try #require(URL(string: "http://127.0.0.1:49999/"))
        tab.load(refused)
        try await waitUntil { tab.loadFailure.error != nil }

        #expect(tab.loadFailure.error?.kind == .cannotConnect)
        #expect(tab.loadFailure.error?.host == "127.0.0.1")
        #expect(tab.url?.host() == "127.0.0.1")
        #expect(tab.displayedURL?.host() == "127.0.0.1")
        #expect(tab.security == .none)

        tab.load(TestPages.url("suite"))
        #expect(tab.loadFailure.error == nil)
        try await waitUntil { tab.title == "suite" && !tab.isLoading }
    }

    @Test func `back from a failed load returns to the page it was leaving`() async throws {
        let manager = TabManager(websiteDataStore: .nonPersistent())
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        let page = TestPages.url("page")
        tab.load(page)
        try await waitUntil { tab.title == "page" && !tab.isLoading }
        #expect(!tab.canGoBack)

        try tab.load(#require(URL(string: "http://127.0.0.1:49999/")))
        try await waitUntil { tab.loadFailure.error != nil }
        #expect(tab.canGoBack)

        tab.goBack()
        #expect(tab.loadFailure.error == nil)
        #expect(tab.displayedURL == page)
        #expect(!tab.canGoBack)
    }

    /// Review ON14: a local file the app can no longer read (moved, or chosen before a relaunch outside the Downloads
    /// folder) shows why, with the file panel, instead of a blank page; restored or opened.
    @Test func `an unreadable local file shows why instead of a blank page`() {
        let missing = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).html")
        let tab = BrowserTab(configuration: WKWebViewConfiguration())
        tab.load(missing)
        #expect(tab.loadFailure.error?.kind == .fileUnreadable)
        #expect(tab.url == missing)

        let stored = StoredTab(id: UUID(), url: missing, title: "Notes", lastActivity: .now)
        let restored = BrowserTab(restoring: stored, configuration: WKWebViewConfiguration())
        restored.makeWebViewIfNeeded()
        #expect(restored.loadFailure.error == PageLoadError(unreadableFile: missing))
    }
}
