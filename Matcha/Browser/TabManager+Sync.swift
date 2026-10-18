import Foundation

/// Changements reçus d'un autre Mac (tâche 7.4, `SYNC.md` § 2.4).
extension TabManager {
    /// Reprend les onglets et le rangement enregistrés, changés par la synchro. Un onglet déjà là garde sa vue web ; s'il
    /// n'est pas affiché et que son adresse a changé, il se décharge et chargera la nouvelle à sa prochaine ouverture. Un
    /// onglet arrivé n'est ni chargé ni sélectionné. Une page affichée ne change pas sous les yeux de l'utilisateur : un
    /// onglet affiché fermé ailleurs reste là, à sa place, jusqu'à ce qu'il le ferme.
    func reconcile(tabs stored: [StoredTab], layout newLayout: SidebarLayout) {
        let displayed = Set(displayedTabIDs)
        var target = newLayout
        for id in displayed where target.place(of: id) == nil {
            switch layout.place(of: id) {
            case .favorite: target.setPlace(id, to: .favorite)
            case .pinned: target.setPlace(id, to: .pinned)
            case .today: target.insertToday(id, at: layout.today.firstIndex(of: id) ?? 0)
            case nil: break
            }
        }
        for entry in stored where target.place(of: entry.id) != nil {
            if let tab = tab(withID: entry.id) {
                update(tab, from: entry, isDisplayed: displayed.contains(entry.id))
            } else {
                let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: websiteDataStore)
                register(BrowserTab(restoring: entry, configuration: configuration))
            }
        }
        for tab in tabs where target.place(of: tab.id) == nil {
            discard(tab)
        }
        updateLayout { $0 = target }
        if let selectedTabID, tab(withID: selectedTabID) == nil {
            setSelection(nil)
        }
    }

    private func update(_ tab: BrowserTab, from entry: StoredTab, isDisplayed: Bool) {
        tab.pinnedURL = entry.pinnedURL
        tab.pinnedTitle = entry.pinnedTitle
        guard !isDisplayed, tab.url != entry.url || !tab.isLoaded && tab.title != entry.title else {
            return
        }
        tab.unload(resettingTo: entry.url, title: entry.title)
    }
}
