import AppKit
import OSLog
import WebKit

/// Menu of a page (right-click outside a link, an image or selected text), as in Chrome: Back, Forward, Reload;
/// Save As…, Print…; View Page Source (and “Inspect Element” with the developer tools). See
/// `PageMenuPlan.pageLayout`.
extension BrowserWebView {
    /// Rewrites `menu` if it is the menu of a page; false otherwise.
    func addPageCommands(to menu: NSMenu) -> Bool {
        let originals = menu.items
        let separators = Set(originals.indices.filter { originals[$0].isSeparatorItem })
        guard let layout = PageMenuPlan.pageLayout(for: originals.map { $0.identifier?.rawValue }, separators: separators) else {
            return false
        }
        // Menu icons (macOS 26 and later): only if WebKit puts some on its own items.
        let showsImages = originals.contains { $0.image != nil }
        menu.removeAllItems()
        for entry in layout {
            switch entry {
            case let .webKit(index):
                menu.addItem(originals[index])
            case .separator:
                menu.addItem(.separator())
            case let .command(command):
                menu.addItem(menuItem(for: command, showsImage: showsImages))
            }
        }
        return true
    }

    private func menuItem(for command: PageCommand, showsImage: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: command.title, action: #selector(performPageCommand(_:)), keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier(command.identifier)
        item.target = self
        item.representedObject = command.rawValue
        // WebKit does not let AppKit enable the items of its menu (`autoenablesItems` false).
        item.isEnabled = switch command {
        case .goBack: canGoBack
        case .goForward: canGoForward
        // The document on screen (its history entry), not a load that started (review TR1).
        case .saveAs, .print: backForwardList.currentItem?.url != nil
        case .viewSource: PageSource.viewerURL(for: backForwardList.currentItem?.url) != nil
        }
        if showsImage {
            item.image = NSImage(systemSymbolName: command.symbolName, accessibilityDescription: nil)
        }
        return item
    }

    @objc private func performPageCommand(_ sender: NSMenuItem) {
        guard let command = (sender.representedObject as? String).flatMap(PageCommand.init(rawValue:)) else {
            return
        }
        // Through the page, like the toolbar's buttons (review WB21): a failure shown, a page woken from sleep or after a
        // crash go back the same way. Without one, the view itself.
        if let delegate = uiDelegate as? any PageMenuDelegate {
            delegate.pageMenu(perform: command, in: self)
        } else if command == .goBack {
            goBack()
        } else if command == .goForward {
            goForward()
        }
        Logger.browser.info("Page menu: \(command.rawValue, privacy: .public)")
    }
}

private extension PageCommand {
    var title: String {
        switch self {
        case .goBack: String(localized: "Back")
        case .goForward: String(localized: "Forward")
        case .saveAs: String(localized: "Save As…", comment: "Context menu of a web page: saves it as a web archive or its source")
        case .print: String(localized: "Print…")
        case .viewSource: String(localized: "View Page Source", comment: "Context menu of a web page: opens its source in a new tab")
        }
    }

    var symbolName: String {
        switch self {
        case .goBack: "chevron.backward"
        case .goForward: "chevron.forward"
        case .saveAs: "square.and.arrow.down"
        case .print: "printer"
        case .viewSource: "chevron.left.forwardslash.chevron.right"
        }
    }
}
