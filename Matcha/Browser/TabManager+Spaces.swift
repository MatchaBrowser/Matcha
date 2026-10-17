import Foundation

/// Restauration, enregistrement et échanges d'onglets entre Spaces.
extension TabManager {
    // MARK: Enregistrement

    /// Remet les onglets enregistrés, sans vue web : chacun la crée à son premier affichage.
    /// L'onglet utilisé le plus récemment est sélectionné, sans charger sa page : elle se charge quand
    /// le Space s'affiche (`loadSelectedTab`).
    func restore(tabs stored: [StoredTab], layout restoredLayout: SidebarLayout) {
        var restored: [BrowserTab] = []
        for entry in stored where restoredLayout.place(of: entry.id) != nil {
            let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: websiteDataStore)
            let tab = BrowserTab(restoring: entry, configuration: configuration)
            register(tab)
            restored.append(tab)
        }
        var known = restoredLayout
        for id in restoredLayout.orderedTabIDs where tab(withID: id) == nil {
            known.remove(id)
        }
        updateLayout { $0 = known }
        restoreSelection(restored.max { $0.lastActivity < $1.lastActivity }?.id)
    }

    /// Crée la vue web des onglets affichés (l'onglet sélectionné et son split), pour les afficher (Space
    /// affiché, lancement).
    func loadSelectedTab() {
        displayedTabs.forEach { $0.makeWebViewIfNeeded() }
    }

    /// Ce qu'il faut enregistrer de chaque onglet rangé.
    func storedTabs() -> [StoredTab] {
        tabs.map { tab in
            StoredTab(
                id: tab.id,
                url: tab.url,
                title: tab.title,
                pinnedURL: tab.pinnedURL,
                pinnedTitle: tab.pinnedTitle,
                lastActivity: tab.lastActivity,
                interactionState: tab.savedInteractionState,
            )
        }
    }

    /// Retient l'état de navigation de chaque onglet chargé (fermeture de l'app).
    func captureInteractionStates() {
        tabs.forEach { $0.captureInteractionState() }
    }

    // MARK: Entre Spaces

    /// Reprend les favoris de `other`, un autre Space du même profil : mêmes onglets, mêmes vues web.
    /// Leurs fenêtres et liens s'ouvrent désormais dans ce Space-ci.
    func adoptFavorites(from other: TabManager) {
        guard other !== self else {
            return
        }
        let adopted = other.layout.favorites.compactMap(other.tab(withID:))
        for id in layout.favorites where !adopted.contains(where: { $0.id == id }) {
            unregister(id)
        }
        adopted.forEach(register)
        updateLayout { $0.setFavorites(adopted.map(\.id)) }
        if let selectedTabID, tab(withID: selectedTabID) == nil {
            setSelection(nil)
        }
    }

    /// Retire l'onglet de ce Space sans le fermer, pour l'envoyer dans un autre Space du même profil.
    @discardableResult
    func detach(_ tab: BrowserTab) -> BrowserTab? {
        guard self.tab(withID: tab.id) != nil else {
            return nil
        }
        moveSelection(awayFrom: tab) {
            updateLayout { $0.remove(tab.id) }
            unregister(tab.id)
        }
        return tab
    }

    /// Accueille un onglet venu d'un autre Space, en tête des onglets du jour.
    func attach(_ tab: BrowserTab) {
        register(tab)
        tab.pinnedURL = nil
        tab.pinnedTitle = nil
        updateLayout { $0.insertToday(tab.id, at: 0) }
        if selectedTab == nil {
            setSelection(tab.id)
        }
    }
}
