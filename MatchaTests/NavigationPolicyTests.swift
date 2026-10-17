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
        button: Int = 0,
        mainFrame: Bool = true,
        handled: Bool = true,
    ) -> NavigationRequest {
        NavigationRequest(
            url: url,
            navigationType: type,
            modifierFlags: modifiers,
            buttonNumber: button,
            targetsMainFrame: mainFrame,
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

    @Test func `middle click opens a background tab`() {
        #expect(NavigationPolicy.decide(request(button: 2)) == .openInNewTab(page, inBackground: true))
    }

    @Test func `command shift click opens a foreground tab`() {
        #expect(NavigationPolicy.decide(request(modifiers: [.command, .shift])) == .openInNewTab(page, inBackground: false))
    }

    @Test func `right click or option click is allowed`() {
        #expect(NavigationPolicy.decide(request(button: 1)) == .allow)
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
    }

    @Test func `foreign scheme wins over modifiers`() throws {
        let url = try #require(URL(string: "mailto:moi@example.com"))
        #expect(NavigationPolicy.decide(request(url: url, modifiers: .command, handled: false)) == .openExternally(url))
    }
}
