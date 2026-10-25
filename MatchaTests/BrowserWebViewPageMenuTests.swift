import AppKit
@testable import Matcha
import Testing
import WebKit

/// Target of the items of a fake WebKit menu: keeps the items that triggered it.
@MainActor
final class FakeWebKitMenuTarget: NSObject {
    private(set) var senders: [NSMenuItem] = []

    @objc func forwardContextMenuAction(_ sender: NSMenuItem) {
        senders.append(sender)
    }
}

/// UI delegate of a web view, which says whether “Open Link in Peek” makes sense.
@MainActor
final class FakePageMenuDelegate: NSObject, WKUIDelegate, PageMenuDelegate {
    var offersPeek: Bool

    init(offersPeek: Bool) {
        self.offersPeek = offersPeek
    }

    func pageMenuOffersPeek(in _: WKWebView) -> Bool {
        offersPeek
    }

    /// Page commands requested (save, print, page source).
    private(set) var performed: [PageCommand] = []

    func pageMenu(perform command: PageCommand, in _: WKWebView) {
        performed.append(command)
    }
}

/// Page context menu (task 5.9) on a fake menu that reproduces the identifiers, action and state of WebKit's
/// items (taken from a real menu, `PageMenuIntegrationTests`).
@MainActor
@Suite(.webKit)
struct BrowserWebViewPageMenuTests {
    private let webView = BrowserWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private let target = FakeWebKitMenuTarget()
    private let delegate = FakePageMenuDelegate(offersPeek: true)

    init() {
        webView.uiDelegate = delegate
    }

    /// WebKit menu: one item per identifier (nil: separator), with an icon as on macOS 26 and later.
    private func webKitMenu(_ identifiers: [String?], target: AnyObject? = nil, withImages: Bool = true) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for identifier in identifiers {
            guard let identifier else {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(
                title: identifier,
                action: #selector(FakeWebKitMenuTarget.forwardContextMenuAction(_:)),
                keyEquivalent: "",
            )
            item.identifier = NSUserInterfaceItemIdentifier(identifier)
            item.target = target ?? self.target
            item.image = withImages ? NSImage(systemSymbolName: "safari", accessibilityDescription: nil) : nil
            menu.addItem(item)
        }
        return menu
    }

    private func choices(in menu: NSMenu) -> [PageMenuItem?] {
        menu.items.map { ($0.representedObject as? PageMenuChoice)?.item }
    }

    private func identifiers(in menu: NSMenu) -> [String?] {
        menu.items.map { $0.identifier?.rawValue }
    }

    @Test func `a link gets a new tab and Peek right after Open Link`() {
        let menu = webKitMenu(PageMenuPlanTests.linkMenu)
        let original = menu.items[1]
        webView.rewritePageMenu(menu)

        #expect(choices(in: menu) == [nil, .openLinkInNewTab, .openLinkInPeek, nil, nil, nil, nil])
        #expect(identifiers(in: menu) == [
            "WKMenuItemIdentifierOpenLink", "MatchaMenuItemIdentifierOpenLinkInNewTab", "MatchaMenuItemIdentifierOpenLinkInPeek",
            "WKMenuItemIdentifierDownloadLinkedFile", "WKMenuItemIdentifierCopyLink", nil, "WKMenuItemIdentifierShareMenu",
        ])
        #expect(menu.items[5].isSeparatorItem)
        for item in menu.items[1 ... 2] {
            #expect(!item.title.isEmpty && item.title != original.title)
            #expect(item.target === webView)
            #expect(item.isEnabled)
            #expect(item.image != nil)
            #expect((item.representedObject as? PageMenuChoice)?.original === original)
        }
    }

    @Test func `no Peek where the delegate does not offer it`() {
        delegate.offersPeek = false
        let menu = webKitMenu(PageMenuPlanTests.linkMenu)
        webView.rewritePageMenu(menu)
        #expect(choices(in: menu) == [nil, .openLinkInNewTab, nil, nil, nil, nil])

        // Without a UI delegate: no Peek either.
        let lonely = BrowserWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let other = webKitMenu(PageMenuPlanTests.linkMenu)
        lonely.rewritePageMenu(other)
        #expect(choices(in: other) == [nil, .openLinkInNewTab, nil, nil, nil, nil])
    }

    @Test func `an image gets a new tab in place of the new window`() {
        let menu = webKitMenu(PageMenuPlanTests.imageMenu)
        webView.rewritePageMenu(menu)
        #expect(choices(in: menu) == [.openImageInNewTab, nil, nil, nil, nil, nil])
        #expect(!identifiers(in: menu).contains("WKMenuItemIdentifierOpenImageInNewWindow"))
    }

    @Test func `a menu without the expected identifiers keeps its items`() {
        let menu = webKitMenu(["WKMenuItemIdentifierOpenLink", "WKMenuItemIdentifierOpenLinkInNewTab", "WKMenuItemIdentifierCopyLink", nil])
        let items = menu.items
        webView.rewritePageMenu(menu)
        #expect(menu.items.count == items.count)
        #expect(zip(menu.items, items).allSatisfy { $0 === $1 })
    }

    @Test func `a WebKit item without action is kept`() {
        let menu = webKitMenu(PageMenuPlanTests.linkMenu)
        let original = menu.items[1]
        original.action = nil
        webView.rewritePageMenu(menu)
        #expect(menu.items[1] === original)
        #expect(choices(in: menu).allSatisfy { $0 == nil })
    }

    @Test func `a disabled WebKit item gives a disabled item, without icon if WebKit has none`() {
        let menu = webKitMenu(PageMenuPlanTests.imageMenu, withImages: false)
        menu.items[0].isEnabled = false
        webView.rewritePageMenu(menu)
        #expect(!menu.items[0].isEnabled)
        #expect(menu.items[0].image == nil)
    }

    /// Choosing the Matcha item triggers the WebKit one (its action, its target, itself as sender), after
    /// remembering the choice.
    @Test(arguments: [(1, PageMenuDestination.backgroundTab), (2, .peek)])
    func `choosing an item triggers the WebKit item with the choice pending`(index: Int, destination: PageMenuDestination) {
        let menu = webKitMenu(PageMenuPlanTests.linkMenu)
        let original = menu.items[1]
        webView.rewritePageMenu(menu)

        menu.performActionForItem(at: index)

        #expect(target.senders.count == 1)
        #expect(target.senders.first === original)
        #expect(webView.pageMenuIntent.intent?.destination == destination)
        let deadline = webView.pageMenuIntent.intent?.deadline ?? .distantPast
        #expect(abs(deadline.timeIntervalSinceNow - PageMenuIntent.lifetime) < 0.5)
    }

    @Test func `a WebKit item that does not answer forgets the choice`() {
        let menu = webKitMenu(PageMenuPlanTests.linkMenu, target: NSObject())
        webView.rewritePageMenu(menu)
        menu.performActionForItem(at: 1)
        #expect(webView.pageMenuIntent.intent == nil)
        #expect(target.senders.isEmpty)
    }

    @Test func `opening another menu forgets a pending choice`() {
        webView.pageMenuIntent.choose(.peek, openingPoint: PeekLayout.center, at: .now)
        webView.rewritePageMenu(webKitMenu(["WKMenuItemIdentifierReload", nil]))
        #expect(webView.pageMenuIntent.intent == nil)
    }

    // MARK: Page menu

    @Test func `the page menu gets back, forward, save, print and source`() {
        let menu = webKitMenu(["WKMenuItemIdentifierReload"])
        webView.rewritePageMenu(menu)
        let identifiers = menu.items.map { $0.isSeparatorItem ? nil : $0.identifier?.rawValue }
        #expect(identifiers == [
            "MatchaMenuItemIdentifierGoBack", "MatchaMenuItemIdentifierGoForward", "WKMenuItemIdentifierReload", nil,
            "MatchaMenuItemIdentifierSaveAs", "MatchaMenuItemIdentifierPrint", nil, "MatchaMenuItemIdentifierViewSource",
        ])
        // Page without history or address: nothing is possible.
        #expect(menu.items.filter { $0.identifier?.rawValue.hasPrefix("MatchaMenuItemIdentifier") == true }.allSatisfy { !$0.isEnabled })
        #expect(menu.items[0].image != nil)
    }

    @Test func `save, print and source go to the delegate`() throws {
        let menu = webKitMenu(["WKMenuItemIdentifierReload"])
        webView.rewritePageMenu(menu)
        for identifier in ["MatchaMenuItemIdentifierSaveAs", "MatchaMenuItemIdentifierPrint", "MatchaMenuItemIdentifierViewSource"] {
            // Disabled on this page without an address: their action is sent directly.
            let item = try #require(menu.items.first { $0.identifier?.rawValue == identifier })
            try NSApp.sendAction(#require(item.action), to: item.target, from: item)
        }
        #expect(delegate.performed == [.saveAs, .print, .viewSource])
    }
}
