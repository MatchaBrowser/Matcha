import AppKit
@testable import Matcha
import Testing
import WebKit

/// Cible des éléments d'un faux menu de WebKit : garde les éléments qui l'ont déclenchée.
@MainActor
final class FakeWebKitMenuTarget: NSObject {
    private(set) var senders: [NSMenuItem] = []

    @objc func forwardContextMenuAction(_ sender: NSMenuItem) {
        senders.append(sender)
    }
}

/// Délégué d'interface d'une vue web, qui dit si « Ouvrir dans un aperçu » a un sens.
@MainActor
final class FakePageMenuDelegate: NSObject, WKUIDelegate, PageMenuDelegate {
    var offersPeek: Bool

    init(offersPeek: Bool) {
        self.offersPeek = offersPeek
    }

    func pageMenuOffersPeek(in _: WKWebView) -> Bool {
        offersPeek
    }

    /// Commandes de la page demandées (enregistrer, imprimer, code source).
    private(set) var performed: [PageCommand] = []

    func pageMenu(perform command: PageCommand, in _: WKWebView) {
        performed.append(command)
    }
}

/// Menu contextuel des pages (tâche 5.9) sur un faux menu qui reprend les identifiants, l'action et l'état des
/// éléments de WebKit (relevés sur un vrai menu, `PageMenuIntegrationTests`).
@MainActor
struct BrowserWebViewPageMenuTests {
    private let webView = BrowserWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private let target = FakeWebKitMenuTarget()
    private let delegate = FakePageMenuDelegate(offersPeek: true)

    init() {
        webView.uiDelegate = delegate
    }

    /// Menu de WebKit : un élément par identifiant (nil : séparateur), avec icône comme sur macOS 26 et plus.
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

        // Sans délégué d'interface : pas d'aperçu non plus.
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

    /// Choisir l'élément de Matcha déclenche celui de WebKit (son action, sa cible, lui-même comme expéditeur), après
    /// avoir retenu le choix.
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

    // MARK: Menu d'une page

    @Test func `the page menu gets back, forward, save, print and source`() {
        let menu = webKitMenu(["WKMenuItemIdentifierReload"])
        webView.rewritePageMenu(menu)
        let identifiers = menu.items.map { $0.isSeparatorItem ? nil : $0.identifier?.rawValue }
        #expect(identifiers == [
            "MatchaMenuItemIdentifierGoBack", "MatchaMenuItemIdentifierGoForward", "WKMenuItemIdentifierReload", nil,
            "MatchaMenuItemIdentifierSaveAs", "MatchaMenuItemIdentifierPrint", nil, "MatchaMenuItemIdentifierViewSource",
        ])
        // Page sans historique ni adresse : rien n'est possible.
        #expect(menu.items.filter { $0.identifier?.rawValue.hasPrefix("MatchaMenuItemIdentifier") == true }.allSatisfy { !$0.isEnabled })
        #expect(menu.items[0].image != nil)
    }

    @Test func `save, print and source go to the delegate`() throws {
        let menu = webKitMenu(["WKMenuItemIdentifierReload"])
        webView.rewritePageMenu(menu)
        for identifier in ["MatchaMenuItemIdentifierSaveAs", "MatchaMenuItemIdentifierPrint", "MatchaMenuItemIdentifierViewSource"] {
            // Désactivés sur cette page sans adresse : leur action est envoyée directement.
            let item = try #require(menu.items.first { $0.identifier?.rawValue == identifier })
            try NSApp.sendAction(#require(item.action), to: item.target, from: item)
        }
        #expect(delegate.performed == [.saveAs, .print, .viewSource])
    }
}
