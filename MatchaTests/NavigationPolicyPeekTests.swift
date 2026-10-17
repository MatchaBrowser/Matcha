import AppKit
@testable import Matcha
import Testing
import WebKit

/// Règles de l'aperçu (Peek, tâche 4.4) : Maj+clic, liens dans l'aperçu, liens d'un favori ou d'un épinglé.
struct NavigationPolicyPeekTests {
    private static let link = "https://example.org/target"
    private static let start = "https://example.com/start"

    private func request(
        url: String = link,
        modifiers: NSEvent.ModifierFlags = .shift,
        button: Int = 1,
        type: WKNavigationType = .linkActivated,
        mainFrame: Bool = true,
        newWindow: Bool = false,
        pageURL: String? = start,
        download: Bool = false,
        source: NavigationSource = .tab,
        otherSites: Bool = false,
        handled: Bool = true,
    ) -> NavigationRequest {
        NavigationRequest(
            url: URL(string: url),
            navigationType: type,
            modifierFlags: modifiers,
            buttonNumber: button,
            targetsMainFrame: mainFrame,
            isSchemeHandledByWebView: handled,
            opensNewWindow: newWindow,
            pageURL: pageURL.flatMap(URL.init(string:)),
            shouldPerformDownload: download,
            source: source,
            opensOtherSitesInPeek: otherSites,
        )
    }

    private func peek(_ text: String = link) -> NavigationDecision {
        .openInPeek(URL(string: text)!)
    }

    // MARK: Maj+clic

    /// Bouton gauche, ou Maj+Entrée sur un lien ; un clic simulé n'emporte jamais Maj, mais la règle n'en dépend pas.
    @Test(arguments: [1, 0])
    func `shift click opens the link in Peek`(button: Int) {
        #expect(NavigationPolicy.decide(request(button: button)) == peek())
    }

    @Test func `shift click on a link opening a new window opens Peek`() {
        #expect(NavigationPolicy.decide(request(newWindow: true)) == peek())
    }

    @Test func `shift click in a subframe opens Peek`() {
        #expect(NavigationPolicy.decide(request(mainFrame: false)) == peek())
    }

    @Test func `caps lock and fn do not prevent Peek`() {
        #expect(NavigationPolicy.decide(request(modifiers: [.shift, .capsLock, .function, .numericPad])) == peek())
    }

    @Test(arguments: [NSEvent.ModifierFlags([.shift, .option]), [.shift, .control]])
    func `shift with option or control is allowed`(modifiers: NSEvent.ModifierFlags) {
        #expect(NavigationPolicy.decide(request(modifiers: modifiers)) == .allow)
    }

    @Test func `shift middle click opens a foreground tab`() throws {
        let url = try #require(URL(string: Self.link))
        #expect(NavigationPolicy.decide(request(button: 4)) == .openInNewTab(url, inBackground: false))
    }

    @Test func `command shift click still opens a foreground tab`() throws {
        let url = try #require(URL(string: Self.link))
        #expect(NavigationPolicy.decide(request(modifiers: [.command, .shift])) == .openInNewTab(url, inBackground: false))
    }

    @Test func `middle click alone opens a background tab`() throws {
        let url = try #require(URL(string: Self.link))
        #expect(NavigationPolicy.decide(request(modifiers: [], button: 4)) == .openInNewTab(url, inBackground: true))
    }

    @Test func `shift click on a download link is allowed`() {
        #expect(NavigationPolicy.decide(request(download: true)) == .allow)
    }

    @Test(arguments: [start, "\(start)#a"])
    func `anchor of the shown page is followed`(page: String) {
        #expect(NavigationPolicy.decide(request(url: "\(Self.start)#part", pageURL: page)) == .allow)
    }

    @Test func `anchor of another page opens Peek`() {
        let other = "https://example.com/other#part"
        #expect(NavigationPolicy.decide(request(url: other)) == peek(other))
    }

    @Test func `anchor in a new window opens Peek`() {
        let anchor = "\(Self.start)#part"
        #expect(NavigationPolicy.decide(request(url: anchor, newWindow: true)) == peek(anchor))
    }

    @Test func `shift on a form submission is allowed`() {
        #expect(NavigationPolicy.decide(request(type: .formSubmitted)) == .allow)
    }

    @Test func `shift click on a foreign scheme opens the other app`() throws {
        let url = try #require(URL(string: "mailto:moi@example.com"))
        #expect(NavigationPolicy.decide(request(url: url.absoluteString, handled: false)) == .openExternally(url))
    }

    @Test(arguments: ["about:blank", "data:text/html,salut", "blob:https://example.com/1234", "javascript:void(0)"])
    func `shift click on about data blob links is allowed`(link: String) {
        #expect(NavigationPolicy.decide(request(url: link)) == .allow)
    }

    @Test func `shift click on a file link opens Peek`() {
        let file = "file:///usr/share/doc/postfix/html/BASIC_CONFIGURATION_README.html"
        #expect(NavigationPolicy.decide(request(url: file, pageURL: "file:///usr/share/doc/postfix/html/index.html")) == peek(file))
    }

    // MARK: Dans l'aperçu

    @Test func `links inside Peek stay in Peek`() {
        #expect(NavigationPolicy.decide(request(modifiers: [], source: .peek)) == .allow)
        #expect(NavigationPolicy.decide(request(source: .peek)) == .allow)
        #expect(NavigationPolicy.decide(request(modifiers: [], newWindow: true, source: .peek)) == peek())
        #expect(NavigationPolicy.decide(request(modifiers: .option, newWindow: true, source: .peek)) == peek())
    }

    @Test func `download inside Peek is allowed`() {
        #expect(NavigationPolicy.decide(request(modifiers: [], newWindow: true, download: true, source: .peek)) == .allow)
    }

    @Test func `command or middle click inside Peek opens a background tab`() throws {
        let url = try #require(URL(string: Self.link))
        #expect(NavigationPolicy.decide(request(modifiers: .command, source: .peek)) == .openInNewTab(url, inBackground: true))
        #expect(NavigationPolicy.decide(request(modifiers: [], button: 4, source: .peek)) == .openInNewTab(url, inBackground: true))
    }

    @Test func `web views outside the tab manager never open Peek`() {
        #expect(NavigationPolicy.decide(request(source: .other)) == .allow)
        #expect(NavigationPolicy.decide(request(newWindow: true, source: .other)) == .allow)
        #expect(NavigationPolicy.decide(request(modifiers: [], source: .other, otherSites: true)) == .allow)
    }

    // MARK: Favoris et épinglés (réglage)

    /// Clic gauche sans touche depuis un favori ou un épinglé, réglage activé.
    private func pinned(
        url: String = link,
        modifiers: NSEvent.ModifierFlags = [],
        button: Int = 1,
        type: WKNavigationType = .linkActivated,
        mainFrame: Bool = true,
        newWindow: Bool = false,
        pageURL: String = start,
        download: Bool = false,
        otherSites: Bool = true,
    ) -> NavigationDecision {
        NavigationPolicy.decide(request(
            url: url,
            modifiers: modifiers,
            button: button,
            type: type,
            mainFrame: mainFrame,
            newWindow: newWindow,
            pageURL: pageURL,
            download: download,
            otherSites: otherSites,
        ))
    }

    @Test func `pinned link to another site opens Peek`() {
        #expect(pinned() == peek())
    }

    @Test(arguments: ["https://accounts.example.com/login", "http://example.com/autre", "https://www.example.com:8443/page"])
    func `pinned link to the same site is allowed`(link: String) {
        #expect(pinned(url: link) == .allow)
    }

    @Test func `pinned link opening a new window to another site opens Peek`() {
        #expect(pinned(newWindow: true) == peek())
    }

    @Test func `pinned link in a subframe is allowed`() {
        #expect(pinned(mainFrame: false) == .allow)
    }

    @Test func `pinned link with the option off is allowed`() {
        #expect(pinned(otherSites: false) == .allow)
    }

    @Test func `pinned link with option key is allowed`() {
        #expect(pinned(modifiers: .option) == .allow)
    }

    @Test func `pinned click simulated by the page is allowed`() {
        #expect(pinned(button: 0) == .allow)
    }

    @Test func `pinned link from or to a file page is allowed`() {
        #expect(pinned(pageURL: "file:///usr/share/doc/postfix/html/index.html") == .allow)
        #expect(pinned(url: "file:///usr/share/doc/postfix/html/index.html") == .allow)
    }

    @Test func `pinned download is allowed`() {
        #expect(pinned(download: true) == .allow)
    }

    @Test func `pinned script navigation is allowed`() {
        #expect(pinned(type: .other) == .allow)
    }
}
