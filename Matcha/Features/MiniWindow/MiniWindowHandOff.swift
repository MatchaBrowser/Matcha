import Foundation

/// Passage de la page d'une mini-fenêtre dans un Space (« Ouvrir dans le Space »).
@MainActor
enum MiniWindowHandOff {
    /// Met la page en tête des onglets du jour de `space`, seule, et la sélectionne ; renvoie l'onglet du Space.
    /// Même profil : c'est le même onglet, avec sa vue web (rien n'est rechargé, l'historique
    /// précédent/suivant et l'état de la page restent). Autre profil : un nouvel onglet charge l'adresse
    /// avec les cookies de ce profil, et la page de la mini-fenêtre est libérée.
    /// Nil si la page n'a pas d'adresse (rien à ouvrir).
    @discardableResult
    static func move(_ tab: BrowserTab, profileID: UUID?, to space: SpaceSession) -> BrowserTab? {
        guard let url = tab.url else {
            return nil
        }
        let tabManager = space.tabManager
        guard space.record.profile?.id == profileID else {
            tab.unload(resettingTo: nil, title: nil)
            return tabManager.newTab(url: url)
        }
        // Même rangement qu'un aperçu ouvert en onglet (tâche 4.4) : en tête, hors de tout split, sélectionné.
        tabManager.insert(tab, after: nil, select: true)
        return tab
    }
}
