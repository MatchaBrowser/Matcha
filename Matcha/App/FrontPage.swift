import Foundation

/// Page visée par les commandes de page : recherche (⌘F, ⌘G, ⇧⌘G ; tâche 5.3), impression, export en PDF et zoom
/// (⌘P, ⌘+, ⌘-, ⌘0 ; tâche 5.4). C'est celle de la mini-fenêtre active, sinon la page au premier plan de la fenêtre
/// de navigation active (l'aperçu s'il est ouvert, sinon l'onglet sélectionné, panneau actif d'un split). Nil sans
/// page chargée : onglet vide ou déchargé, aucune fenêtre de navigation active (Réglages), mini-fenêtre vide.
@MainActor
enum FrontPage {
    static func page(miniWindowTab: BrowserTab?, tabManager: TabManager?) -> BrowserTab? {
        // Une mini-fenêtre active sans page ne renvoie jamais à la fenêtre de navigation derrière elle.
        guard let page = miniWindowTab ?? tabManager?.frontTab, page.hasURL, page.isLoaded else {
            return nil
        }
        return page
    }
}
