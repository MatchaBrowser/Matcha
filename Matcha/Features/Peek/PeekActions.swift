import AppKit
import Foundation
import WebKit

/// Fermer l'aperçu, l'ouvrir en onglet ; le clavier suit.
@MainActor
enum PeekActions {
    /// Bulle d'aide et libellé du ×, élément du menu Fichier à la place de « Fermer l'onglet » (⌘W).
    static let closeTitle = LocalizedStringResource(
        "Close Peek",
        comment: "Peek: help tag and accessibility label of the × button; File menu item replacing “Close Tab” (⌘W) while a peek is open",
    )

    /// ⎋, ⌘W, ×, clic à côté, `window.close()` : l'aperçu se ferme, la page d'origine reprend le clavier.
    static func close(in tabManager: TabManager) {
        guard let peek = tabManager.peek else {
            return
        }
        let source = tabManager.tab(withID: peek.sourceTabID) ?? tabManager.selectedTab
        releaseKeyboard(from: peek.tab.webView)
        tabManager.closePeek()
        if let source {
            TabActivation.focusPage(of: source)
        }
    }

    /// « Ouvrir en onglet » : la page passe dans la carte, puis reprend le clavier perdu pendant le déplacement.
    /// La vue web quitte l'aperçu dans la même mise à jour qu'elle entre dans la carte : elle n'a jamais
    /// deux parents (AppKit la retire de son conteneur quand la carte l'ajoute).
    static func openAsTab(in tabManager: TabManager) {
        guard let webView = tabManager.peek?.tab.webView else {
            return
        }
        let oldHost = webView.superview
        releaseKeyboard(from: webView)
        tabManager.openPeekAsTab()
        PeekFocus.focus(webView, awayFrom: oldHost)
    }

    /// Rend le clavier à la fenêtre s'il est dans la page de l'aperçu (jamais pris à un autre champ).
    private static func releaseKeyboard(from webView: WKWebView?) {
        guard let webView, let window = webView.window, let responder = window.firstResponder as? NSView else {
            return
        }
        if responder === webView || responder.isDescendant(of: webView) {
            window.makeFirstResponder(nil)
        }
    }
}
