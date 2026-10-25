import AppKit
@testable import Matcha
import Testing
import WebKit

struct NavigationPolicyTests {
    private let page = URL(string: "https://example.com/page")!

    private func request(
        url: URL? = URL(string: "https://example.com/page"),
        type: WKNavigationType = .linkActivated,
        modifiers: NSEvent.ModifierFlags = [],
        button: Int = 1,
        mainFrame: Bool = true,
        fromMainFrame: Bool = true,
        handled: Bool = true,
    ) -> NavigationRequest {
        NavigationRequest(
            url: url,
            navigationType: type,
            modifierFlags: modifiers,
            buttonNumber: button,
            targetsMainFrame: mainFrame,
            isFromMainFrame: fromMainFrame,
            isSchemeHandledByWebView: handled,
        )
    }

    @Test func `plain link is allowed`() {
        #expect(NavigationPolicy.decide(request()) == .allow)
    }

    @Test func `missing url is allowed`() {
        #expect(NavigationPolicy.decide(request(url: nil)) == .allow)
    }

    @Test func `command click opens a background tab`() {
        #expect(NavigationPolicy.decide(request(modifiers: .command)) == .openInNewTab(page, inBackground: true))
    }

    /// Audit W6: the app itself only opens web links, or a link to a page of the same kind as the displayed one.
    @Test(arguments: [
        "data:text/html,salut",
        "blob:https://example.com/1234",
        "about:blank",
        "javascript:void(0)",
        "file:///Users/moi/Downloads/a.html"
    ])
    func `command click on a link the app does not open itself stays a plain click`(url: String) {
        let link = URL(string: url)
        #expect(link != nil)
        #expect(NavigationPolicy.decide(request(url: link, modifiers: .command)) == .allow)
        #expect(NavigationPolicy.decide(request(url: link, button: 4)) == .allow)
    }

    @Test func `a local file opens in a new tab from another local file only`() throws {
        let file = try #require(URL(string: "file:///usr/share/doc/postfix/html/index.html"))
        var fromFile = request(url: file, modifiers: .command)
        fromFile.pageURL = URL(string: "file:///usr/share/doc/postfix/html/BASIC_CONFIGURATION_README.html")
        #expect(NavigationPolicy.decide(fromFile) == .openInNewTab(file, inBackground: true))
        var fromWeb = fromFile
        fromWeb.pageURL = page
        #expect(NavigationPolicy.decide(fromWeb) == .allow)
        var webFromFile = request(modifiers: .command)
        webFromFile.pageURL = fromFile.pageURL
        #expect(NavigationPolicy.decide(webFromFile) == .openInNewTab(page, inBackground: true))
    }

    @Test func `middle click opens a background tab`() {
        #expect(NavigationPolicy.decide(request(button: 4)) == .openInNewTab(page, inBackground: true))
    }

    /// WebKit's button mask, checked on real clicks: before 4.4, the middle button was taken for 2 (the right button),
    /// so a wheel click followed the link in place.
    @Test func `button numbers follow WebKit's mask`() {
        #expect(NavigationPolicy.leftMouseButton == 1)
        #expect(NavigationPolicy.middleMouseButton == 4)
        #expect(NavigationPolicy.decide(request(button: 0)) == .allow)
    }

    @Test func `command shift click opens a foreground tab`() {
        #expect(NavigationPolicy.decide(request(modifiers: [.command, .shift])) == .openInNewTab(page, inBackground: false))
    }

    @Test func `right click or option click is allowed`() {
        #expect(NavigationPolicy.decide(request(button: 2)) == .allow)
        #expect(NavigationPolicy.decide(request(modifiers: .option)) == .allow)
    }

    @Test(arguments: [WKNavigationType.formSubmitted, .backForward, .reload, .formResubmitted, .other])
    func `modifiers only matter for link clicks`(type: WKNavigationType) {
        #expect(NavigationPolicy.decide(request(type: type, modifiers: .command)) == .allow)
    }

    @Test(arguments: ["mailto:moi@example.com", "tel:+33123456789", "zoommtg://zoom.us/join?confno=1"])
    func `foreign schemes open in another app`(link: String) throws {
        let url = try #require(URL(string: link))
        #expect(NavigationPolicy.decide(request(url: url, handled: false)) == .openExternally(url))
    }

    @Test func `foreign scheme from a subframe is cancelled`() throws {
        let url = try #require(URL(string: "itms-apps://apps.apple.com/app/id1"))
        #expect(NavigationPolicy.decide(request(url: url, type: .other, mainFrame: false, handled: false)) == .cancel)
        // Review WB1: nor through the main frame or a new window (`window.open` in an ad frame).
        #expect(NavigationPolicy.decide(request(url: url, type: .other, fromMainFrame: false, handled: false)) == .cancel)
    }

    /// Review WB4: file shares and remote sessions are never handed to another app.
    @Test(arguments: ["smb://attaquant/partage", "afp://serveur/x", "vnc://hote", "ssh://hote", "ftp://hote/fichier", "SMB://hote"])
    func `file shares and remote sessions are refused`(link: String) throws {
        let url = try #require(URL(string: link))
        #expect(NavigationPolicy.decide(request(url: url, handled: false)) == .cancel)
    }

    @Test func `foreign scheme wins over modifiers`() throws {
        let url = try #require(URL(string: "mailto:moi@example.com"))
        #expect(NavigationPolicy.decide(request(url: url, modifiers: .command, handled: false)) == .openExternally(url))
    }
}
