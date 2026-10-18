import AppKit
import OSLog
import WebKit

/// Menu d'une page (clic droit hors d'un lien, d'une image ou d'un texte sélectionné), comme dans Chrome : Précédent,
/// Suivant, Recharger ; Enregistrer sous…, Imprimer… ; Afficher le code source (et « Inspecter l'élément » avec les
/// outils pour développeurs). Voir `PageMenuPlan.pageLayout`.
extension BrowserWebView {
    /// Réécrit `menu` s'il est celui d'une page ; faux sinon.
    func addPageCommands(to menu: NSMenu) -> Bool {
        let originals = menu.items
        let separators = Set(originals.indices.filter { originals[$0].isSeparatorItem })
        guard let layout = PageMenuPlan.pageLayout(for: originals.map { $0.identifier?.rawValue }, separators: separators) else {
            return false
        }
        // Icônes des menus (macOS 26 et plus) : seulement si WebKit en met aux siens.
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
        // WebKit ne laisse pas AppKit activer les éléments de son menu (`autoenablesItems` faux).
        item.isEnabled = switch command {
        case .goBack: canGoBack
        case .goForward: canGoForward
        case .saveAs, .print: url != nil
        case .viewSource: PageSource.viewerURL(for: url) != nil
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
        switch command {
        case .goBack:
            goBack()
        case .goForward:
            goForward()
        case .saveAs, .print, .viewSource:
            (uiDelegate as? any PageMenuDelegate)?.pageMenu(perform: command, in: self)
        }
        Logger.browser.info("Menu de la page : \(command.rawValue, privacy: .public)")
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
