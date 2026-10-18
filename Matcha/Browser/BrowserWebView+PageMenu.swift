import AppKit
import OSLog
import WebKit

/// Ce que le menu contextuel d'une page demande au délégué d'interface de sa vue web (`NavigationCoordinator`).
@MainActor
protocol PageMenuDelegate: AnyObject {
    /// Vrai si « Ouvrir dans un aperçu » a un sens dans `webView` : un onglet de la barre (ni l'aperçu, où un lien
    /// se charge déjà sur place, ni une mini-fenêtre ou une fenêtre de connexion, qui n'ont pas d'aperçu).
    func pageMenuOffersPeek(in webView: WKWebView) -> Bool
    /// Enregistrer sous…, Imprimer…, Afficher le code source, choisis dans le menu de la page de `webView`.
    func pageMenu(perform command: PageCommand, in webView: WKWebView)
}

/// Élément de Matcha dans le menu : ce qu'il fait, l'élément de WebKit qu'il déclenche et le point d'où un aperçu
/// grandirait.
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

/// Menu contextuel des pages (tâche 5.9). « Ouvrir le lien dans un nouvel onglet » et « Ouvrir l'image dans un nouvel
/// onglet » prennent la place des éléments « … dans une nouvelle fenêtre » de WebKit ; « Ouvrir dans un aperçu » suit
/// le premier, dans les onglets. Le reste (« Copier le lien », « Télécharger le fichier lié », « Inspecter l'élément »
/// avec les outils pour développeurs…) est le menu de WebKit, inchangé ; sans les identifiants attendus, le menu entier
/// l'est.
///
/// Un élément de Matcha retient le choix (`pageMenuIntent`) puis déclenche l'élément de WebKit qu'il remplace, par
/// `NSApp.sendAction` avec l'action, la cible et l'élément de WebKit eux-mêmes : WebKit ouvre alors la fenêtre du lien,
/// que `NavigationCoordinator` range selon le choix.
extension BrowserWebView {
    /// Réécrit `menu`, que WebKit s'apprête à ouvrir. Un choix encore en attente (menu précédent) est oublié.
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
        // À l'ouverture du menu, le pointeur est sur l'élément cliqué.
        let openingPoint = pointerPeekPoint
        // De la fin vers le début : la place des éléments suivants ne bouge pas.
        for replacement in replacements.reversed() {
            let original = menu.items[replacement.index]
            // Sans action, l'élément de WebKit ne pourrait pas être déclenché : il reste.
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
        // WebKit ne laisse pas AppKit activer ses éléments (`autoenablesItems` faux) : on reprend l'état du sien.
        menuItem.isEnabled = choice.original.isEnabled
        // Icônes des menus (macOS 26 et plus) : seulement si WebKit en met une aux siens.
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
            Logger.browser.notice("Menu contextuel : l'élément de WebKit n'a pas répondu")
            return
        }
        Logger.browser.info("Menu contextuel : \(choice.item.logName, privacy: .public)")
    }
}

extension WKWebView {
    /// Point d'où l'aperçu grandit : le pointeur, en fractions de la vue web (origine en haut à gauche) ; le centre
    /// hors d'une fenêtre.
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

    /// Pour le journal : jamais l'adresse.
    var logName: String {
        switch self {
        case .openLinkInNewTab:
            "lien dans un nouvel onglet"
        case .openLinkInPeek:
            "lien dans un aperçu"
        case .openImageInNewTab:
            "image dans un nouvel onglet"
        }
    }
}
