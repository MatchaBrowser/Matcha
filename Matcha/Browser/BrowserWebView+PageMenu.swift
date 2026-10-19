import AppKit
import OSLog
import WebKit

/// What the context menu of a page asks of the UI delegate of its web view (`NavigationCoordinator`).
@MainActor
protocol PageMenuDelegate: AnyObject {
    /// True if “Open Link in Peek” makes sense in `webView`: a tab of the sidebar (not Peek, where a link already loads
    /// in place, nor a mini window or a sign-in window, which have no Peek).
    func pageMenuOffersPeek(in webView: WKWebView) -> Bool
    /// Save As…, Print…, View Page Source, chosen in the page menu of `webView`.
    func pageMenu(perform command: PageCommand, in webView: WKWebView)
}

/// Matcha item in the menu: what it does, the WebKit item it triggers and the point from which a Peek would
/// grow.
final class PageMenuChoice: NSObject {
    let item: PageMenuItem
    let original: NSMenuItem
    let openingPoint: CGPoint

    init(item: PageMenuItem, original: NSMenuItem, openingPoint: CGPoint) {
        self.item = item
        self.original = original
        self.openingPoint = openingPoint
    }
}

/// Context menu of pages (task 5.9). “Open Link in New Tab” and “Open Image in New Tab” take the place of WebKit's
/// “… in New Window” items; “Open Link in Peek” follows the first one, in tabs. The rest (“Copy Link”, “Download
/// Linked File”, “Inspect Element” with the developer tools…) is WebKit's menu, unchanged; without the expected
/// identifiers, the whole menu is left unchanged.
///
/// A Matcha item records the choice (`pageMenuIntent`) then triggers the WebKit item it replaces, through
/// `NSApp.sendAction` with the WebKit item's own action, target and item: WebKit then opens the link's window, which
/// `NavigationCoordinator` places according to the choice.
extension BrowserWebView {
    /// Rewrites `menu`, which WebKit is about to open. A choice still pending (previous menu) is forgotten.
    func rewritePageMenu(_ menu: NSMenu) {
        pageMenuIntent.cancel()
        if addPageCommands(to: menu) {
            return
        }
        let offersPeek = (uiDelegate as? any PageMenuDelegate)?.pageMenuOffersPeek(in: self) ?? false
        let replacements = PageMenuPlan.replacements(for: menu.items.map { $0.identifier?.rawValue }, offersPeek: offersPeek)
        guard !replacements.isEmpty else {
            return
        }
        // When the menu opens, the pointer is over the clicked element.
        let openingPoint = pointerPeekPoint
        // From the end to the start: the position of the following items does not move.
        for replacement in replacements.reversed() {
            let original = menu.items[replacement.index]
            // Without an action, the WebKit item could not be triggered: it stays.
            guard original.action != nil else {
                continue
            }
            menu.removeItem(at: replacement.index)
            for (offset, item) in replacement.items.enumerated() {
                let choice = PageMenuChoice(item: item, original: original, openingPoint: openingPoint)
                menu.insertItem(menuItem(for: choice), at: replacement.index + offset)
            }
        }
    }

    private func menuItem(for choice: PageMenuChoice) -> NSMenuItem {
        let menuItem = NSMenuItem(title: choice.item.title, action: #selector(performPageMenuChoice(_:)), keyEquivalent: "")
        menuItem.identifier = NSUserInterfaceItemIdentifier(choice.item.identifier)
        menuItem.target = self
        menuItem.representedObject = choice
        // WebKit does not let AppKit enable its items (`autoenablesItems` false): we copy the state of its own item.
        menuItem.isEnabled = choice.original.isEnabled
        // Menu icons (macOS 26 and later): only if WebKit puts one on its own items.
        if choice.original.image != nil {
            menuItem.image = NSImage(systemSymbolName: choice.item.symbolName, accessibilityDescription: nil)
        }
        return menuItem
    }

    @objc private func performPageMenuChoice(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? PageMenuChoice, let action = choice.original.action else {
            return
        }
        pageMenuIntent.choose(choice.item.destination, openingPoint: choice.openingPoint, at: .now)
        guard NSApp.sendAction(action, to: choice.original.target, from: choice.original) else {
            pageMenuIntent.cancel()
            Logger.browser.notice("Context menu: the WebKit item did not respond")
            return
        }
        Logger.browser.info("Context menu: \(choice.item.logName, privacy: .public)")
    }
}

extension WKWebView {
    /// Point from which Peek grows: the pointer, as fractions of the web view (origin at the top left); the center
    /// outside a window.
    var pointerPeekPoint: CGPoint {
        guard let window else {
            return PeekLayout.center
        }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return PeekLayout.fraction(of: point, in: bounds.size, flipped: isFlipped)
    }
}

private extension PageMenuItem {
    var title: String {
        switch self {
        case .openLinkInNewTab:
            String(localized: "Open Link in New Tab", comment: "Context menu of a link in a web page")
        case .openLinkInPeek:
            String(localized: "Open Link in Peek", comment: "Context menu of a link in a web page: opens it in Peek, over the page")
        case .openImageInNewTab:
            String(localized: "Open Image in New Tab", comment: "Context menu of an image in a web page")
        }
    }

    var symbolName: String {
        switch self {
        case .openLinkInNewTab, .openImageInNewTab:
            "plus.square.on.square"
        case .openLinkInPeek:
            "eye"
        }
    }

    /// For the log: never the address.
    var logName: String {
        switch self {
        case .openLinkInNewTab:
            "link in a new tab"
        case .openLinkInPeek:
            "link in a peek"
        case .openImageInNewTab:
            "image in a new tab"
        }
    }
}
