import Foundation
import OSLog
import WebKit

/// Aperçu (Peek, tâche 4.4) : une page ouverte par-dessus les pages affichées, hors de la barre latérale. C'est
/// un `BrowserTab` que la barre ne connaît pas ; « Ouvrir en onglet » range ce même objet : même vue web, même
/// historique, rien n'est rechargé. Il n'est jamais enregistré.
/// Tâche 5.7 : une page d'aperçu plantée est visible (`isVisible`), elle se recharge.
/// Tâche 6.3 : pour les extensions, l'aperçu ouvert est un onglet, juste après son onglet d'origine, et l'onglet actif
/// (`ExtensionWindows`).
extension TabManager {
    /// Page au premier plan : l'aperçu s'il est ouvert, sinon l'onglet sélectionné, qui est aussi le panneau
    /// actif d'un split (⌘R, ⌘[, ⌘], ⇧⌘C ; 5.3, 5.4).
    var frontTab: BrowserTab? {
        peek?.tab ?? selectedTab
    }

    func isPeek(_ webView: WKWebView) -> Bool {
        peek.map { $0.tab.webView === webView } ?? false
    }

    /// Onglet rangé, ou page de l'aperçu, qui possède `webView` (`tab(for:)` reste limité aux onglets rangés).
    func tabOrPeek(for webView: WKWebView) -> BrowserTab? {
        tab(for: webView) ?? (isPeek(webView) ? peek?.tab : nil)
    }

    /// Onglet après lequel ranger ce que `webView` ouvre : le sien, ou pour l'aperçu, son onglet d'origine.
    /// Tâche 5.9 : « Ouvrir dans un nouvel onglet » depuis l'aperçu s'en sert, avec `select: false`.
    func insertionAnchor(for webView: WKWebView) -> BrowserTab? {
        if let tab = tab(for: webView) {
            return tab
        }
        guard let peek, isPeek(webView) else {
            return nil
        }
        return tab(withID: peek.sourceTabID)
    }

    /// Un aperçu ne s'ouvre que par-dessus une page affichée (l'onglet sélectionné ou un panneau de son split),
    /// ou depuis l'aperçu lui-même, qui charge le lien.
    func canPeek(from source: BrowserTab) -> Bool {
        source === peek?.tab || displayedTabIDs.contains(source.id)
    }

    /// Ouvre `url` dans un nouvel aperçu, avec la configuration de `source` (même profil) ; un aperçu déjà ouvert
    /// est d'abord fermé, et un panneau de split devient le panneau actif. Depuis l'aperçu, `url` s'y charge.
    /// Nil si `source` n'est pas affiché. Point d'entrée du menu contextuel des pages (tâche 5.9).
    @discardableResult
    func openPeek(_ url: URL, from source: BrowserTab, openingPoint: CGPoint = PeekLayout.center) -> Peek? {
        if let peek, source === peek.tab {
            peek.tab.load(url)
            return peek
        }
        guard canPeek(from: source) else {
            Logger.peek.notice("Aperçu refusé : l'onglet d'origine n'est pas affiché")
            return nil
        }
        closePeek()
        if source.id != selectedTabID {
            // Panneau d'un split (Maj+Entrée sur un lien) : l'aperçu appartient au panneau actif.
            setSelection(source.id)
        }
        let page = BrowserTab(configuration: source.configuration, openerID: source.id)
        page.delegate = coordinator
        page.load(url)
        let newPeek = Peek(tab: page, sourceTabID: source.id, openingPoint: openingPoint)
        setPeek(newPeek)
        Logger.peek.info("Aperçu ouvert")
        return newPeek
    }

    /// Ferme l'aperçu : sa vue web est libérée (son, processus). Ne touche pas au clavier (`PeekActions`).
    func closePeek() {
        guard let peek else {
            return
        }
        setPeek(nil)
        peek.tab.unload(resettingTo: nil, title: nil)
        Logger.peek.debug("Aperçu fermé")
    }

    /// « Ouvrir en onglet » : la page de l'aperçu devient un onglet du jour, seule, après son onglet d'origine (et
    /// son split) et ceux déjà ouverts depuis lui (en tête s'il est épinglé ou favori), et sélectionné.
    @discardableResult
    func openPeekAsTab() -> BrowserTab? {
        guard let peek else {
            return nil
        }
        setPeek(nil)
        insert(peek.tab, after: tab(withID: peek.sourceTabID), select: true)
        Logger.peek.info("Aperçu ouvert en onglet")
        return peek.tab
    }
}
