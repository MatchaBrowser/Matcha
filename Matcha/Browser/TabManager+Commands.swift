import Foundation
import WebKit

/// Actions groupées sur les onglets : « Effacer » des onglets du jour, « Dupliquer », « Fermer les autres onglets ».
extension TabManager {
    /// Ferme tous les onglets du jour (bouton « Effacer »). Si l'onglet sélectionné en faisait partie,
    /// la sélection passe au dernier onglet restant de la barre.
    func clearToday() {
        let cleared = todayTabs
        let selectionCleared = cleared.contains { $0.id == selectedTabID }
        cleared.forEach(discard)
        if selectionCleared {
            setSelection(layout.orderedTabIDs.last)
        }
    }

    /// Ouvre une copie de l'onglet juste après lui, avec son historique, et la sélectionne.
    @discardableResult
    func duplicate(_ tab: BrowserTab) -> BrowserTab {
        // Même configuration : même profil. L'état d'interaction emporte l'historique précédent/suivant ; celui d'un
        // onglet en veille (tâche 5.6) est son état retenu.
        let copy = insertTab(configuration: tab.configuration, after: tab, select: true)
        let suspendedState = tab.suspension.isSuspended ? tab.savedInteractionState : nil
        if let state = tab.webView?.interactionState ?? suspendedState {
            copy.webView?.interactionState = state
        } else if let url = tab.url {
            copy.load(url)
        }
        return copy
    }

    /// Ferme tous les onglets du jour sauf `tab` et son split ; `tab` est sélectionné, épinglés et favoris restent.
    func closeOtherTabs(than tab: BrowserTab) {
        select(tab)
        let kept = Set(layout.split(containing: tab.id)?.tabIDs ?? [tab.id])
        for other in todayTabs where !kept.contains(other.id) {
            close(other)
        }
    }
}
