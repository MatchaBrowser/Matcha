import Foundation
import OSLog

/// Split view : onglets affichés côte à côte. Le panneau actif est l'onglet sélectionné.
extension TabManager {
    var displayedTabIDs: [BrowserTab.ID] {
        layout.displayedTabIDs(selected: selectedTabID)
    }

    /// Onglets affichés dans la carte, de gauche à droite : le split de l'onglet sélectionné, sinon lui seul.
    var displayedTabs: [BrowserTab] {
        displayedTabIDs.compactMap(tab(withID:))
    }

    /// Split affiché : celui de l'onglet sélectionné.
    var displayedSplit: SplitGroup? {
        selectedTabID.flatMap(layout.split(containing:))
    }

    func split(containing tab: BrowserTab) -> SplitGroup? {
        layout.split(containing: tab.id)
    }

    /// `.unavailable` pour un onglet d'un autre gestionnaire ; sinon face à l'onglet sélectionné.
    func splitAvailability(for tabID: BrowserTab.ID) -> SplitAvailability {
        guard tab(withID: tabID) != nil else {
            return .unavailable
        }
        return layout.splitAvailability(of: tabID, anchor: selectedTabID)
    }

    /// « Ouvrir en split » : à droite du panneau actif.
    @discardableResult
    func openInSplit(_ tab: BrowserTab) -> Bool {
        let active = selectedTabID.flatMap { displayedTabIDs.firstIndex(of: $0) } ?? 0
        return openInSplit(tab, at: active + 1)
    }

    /// Au rang `paneIndex` des panneaux affichés ; l'onglet devient le panneau actif. Faux si refusé.
    @discardableResult
    func openInSplit(_ tab: BrowserTab, at paneIndex: Int) -> Bool {
        guard let selected = selectedTabID, splitAvailability(for: tab.id) == .allowed else {
            return false
        }
        var joined: UUID?
        changingPlaces(of: [tab.id] + displayedTabIDs) { joined = $0.joinSplit(tab.id, anchor: selected, at: paneIndex) }
        guard joined != nil else {
            return false
        }
        setSelection(tab.id)
        let count = displayedTabIDs.count
        Logger.browser.info("Split : \(count, privacy: .public) panneaux")
        return true
    }

    /// « Retirer du split » : l'onglet reste ouvert, juste après le split.
    func removeFromSplit(_ tab: BrowserTab) {
        keepingPanesOnScreen(leaving: tab) {
            updateLayout { $0.removeFromSplit(tab.id) }
        }
    }

    /// « Séparer les onglets » : les onglets gardent leur place ; la sélection ne change pas.
    func separateSplit(_ groupID: UUID) {
        updateLayout { $0.separateSplit(groupID) }
    }

    /// Split du jour : ses onglets sont fermés ; épinglé : ils se déchargent et le split reste.
    /// La sélection passe hors du split.
    func closeSplit(_ groupID: UUID) {
        guard let group = layout.split(withID: groupID), let first = group.tabIDs.first else {
            return
        }
        let members = group.tabIDs.compactMap(tab(withID:))
        if layout.place(of: first) == .pinned {
            moveSelection(awayFrom: Set(group.tabIDs)) {
                members.forEach { $0.unload(resettingTo: $0.pinnedURL, title: $0.pinnedTitle) }
            }
        } else {
            moveSelection(awayFrom: Set(group.tabIDs)) { members.forEach(discard) }
        }
        Logger.browser.info("Split fermé : \(members.count, privacy: .public) panneaux")
    }

    /// Déplace tout le split (glisser-déposer de sa ligne).
    func moveSplit(_ groupID: UUID, to destination: SidebarDestination) {
        guard let group = layout.split(withID: groupID) else {
            return
        }
        changingPlaces(of: group.tabIDs) { $0.moveSplit(groupID, to: destination) }
    }

    /// « Épingler le split » et « Désépingler le split ».
    func setSplitPlace(_ groupID: UUID, to place: TabPlace) {
        guard let group = layout.split(withID: groupID) else {
            return
        }
        changingPlaces(of: group.tabIDs) { $0.setSplitPlace(groupID, to: place) }
    }

    /// Parts de largeur des panneaux, retenues à la fin d'un glissement du séparateur.
    func setSplitFractions(_ groupID: UUID, _ fractions: [Double]) {
        updateLayout { $0.setSplitFractions(groupID, fractions) }
    }

    func hasLoadedTab(inSplit groupID: UUID) -> Bool {
        layout.split(withID: groupID)?.tabIDs.contains { tab(withID: $0)?.isLoaded == true } ?? false
    }

    /// Applique `change` ; si `tab`, panneau actif, a quitté son split, son voisin devient actif : le reste du
    /// split reste affiché.
    func keepingPanesOnScreen(leaving tab: BrowserTab, during change: () -> Void) {
        let neighbor = selectedTabID == tab.id ? layout.split(containing: tab.id)?.neighbor(of: tab.id) : nil
        change()
        guard let neighbor, layout.place(of: neighbor) != nil, layout.split(containing: neighbor)?.contains(tab.id) != true else {
            return
        }
        setSelection(neighbor)
    }

    /// Applique `change` puis met à jour l'adresse d'origine des onglets de `ids` qui ont changé de place.
    private func changingPlaces(of ids: [UUID], _ change: (inout SidebarLayout) -> Void) {
        let previous = Dictionary(ids.map { ($0, layout.place(of: $0)) }) { first, _ in first }
        updateLayout(change)
        for id in ids {
            guard let tab = tab(withID: id), let before = previous[id], layout.place(of: id) != before else {
                continue
            }
            updatePinnedOrigin(of: tab, previousPlace: before)
        }
    }
}
