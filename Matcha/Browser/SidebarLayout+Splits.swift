import Foundation

/// Split view : onglets voisins affichés côte à côte.
///
/// Règles (rétablies par `normalizeSplits` après chaque changement) : les membres d'un split se suivent
/// dans un seul conteneur (onglets du jour, racine des épinglés ou un dossier), dans l'ordre des panneaux ;
/// jamais de favori ; un onglet dans un seul split ; déplacer, épingler, mettre en favori ou retirer un
/// onglet le sort de son split, défait sous deux onglets.
nonisolated extension SidebarLayout {
    func split(containing tabID: UUID) -> SplitGroup? {
        splits.first { $0.contains(tabID) }
    }

    func split(withID id: UUID) -> SplitGroup? {
        splits.first { $0.id == id }
    }

    /// Onglets montrés quand `selected` est sélectionné : son split de gauche à droite, sinon lui seul ; [] si nil.
    func displayedTabIDs(selected: UUID?) -> [UUID] {
        guard let selected else {
            return []
        }
        return split(containing: selected)?.tabIDs ?? [selected]
    }

    /// `tabID` face à ce qu'affiche `anchor` : impossible sans ancre, avec lui-même, un favori, un onglet non
    /// rangé ou un membre du split affiché ; plein à 4 panneaux ; possible sinon.
    func splitAvailability(of tabID: UUID, anchor: UUID?) -> SplitAvailability {
        guard let anchor, anchor != tabID,
              let tabPlace = place(of: tabID), tabPlace != .favorite,
              let anchorPlace = place(of: anchor), anchorPlace != .favorite
        else {
            return .unavailable
        }
        let group = split(containing: anchor)
        if group?.contains(tabID) == true {
            return .unavailable
        }
        return group?.isFull == true ? .full : .allowed
    }

    /// `tabID` rejoint le split de `anchor` (créé avec `newGroupID` au besoin) au rang `paneIndex` ; nil si refusé.
    /// Le split garde la place de l'ancre, sauf un split du jour rejoint par un épinglé : il va à la place de
    /// l'épinglé. S'il faisait partie d'un autre split, l'onglet le quitte.
    @discardableResult
    mutating func joinSplit(_ tabID: UUID, anchor: UUID, at paneIndex: Int, newGroupID: UUID = UUID()) -> UUID? {
        guard splitAvailability(of: tabID, anchor: anchor) == .allowed else {
            return nil
        }
        var group = split(containing: anchor) ?? SplitGroup(id: newGroupID, tabIDs: [anchor])
        // Un épinglé n'est jamais désépinglé sans demande : un split du jour rejoint par un épinglé va chez lui.
        let pinnedWins = place(of: anchor) == .today && place(of: tabID) == .pinned
        guard let start = container(of: pinnedWins ? tabID : group.tabIDs[0]) else {
            return nil
        }
        group.insert(tabID, at: paneIndex)
        let others = splits.filter { $0.id != group.id }.map { other in
            var other = other
            other.remove(tabID)
            return other
        }
        placeTab(group.tabIDs[0], at: start.container.destination(at: start.index))
        for (previous, id) in zip(group.tabIDs, group.tabIDs.dropFirst()) {
            placeTab(id, after: previous)
        }
        setSplits(others + [group])
        return group.id
    }

    /// L'onglet quitte son split et se place juste après le dernier autre membre.
    mutating func removeFromSplit(_ tabID: UUID) {
        guard var group = split(containing: tabID), let last = group.tabIDs.last(where: { $0 != tabID }) else {
            return
        }
        group.remove(tabID)
        placeTab(tabID, after: last)
        setSplits(splits.map { $0.id == group.id ? group : $0 })
    }

    /// Défait le split ; ses onglets gardent leur place.
    mutating func separateSplit(_ groupID: UUID) {
        setSplits(splits.filter { $0.id != groupID })
    }

    /// Déplace tout le split (glisser-déposer), dans l'ordre des panneaux ; refusé vers les favoris.
    mutating func moveSplit(_ groupID: UUID, to destination: SidebarDestination) {
        guard let group = split(withID: groupID), let first = group.tabIDs.first, Container(destination) != .favorites else {
            return
        }
        // Dans le même conteneur, `placeTab` corrige le rang : déposer le split sur sa propre ligne ne change rien.
        placeTab(first, at: destination)
        for (previous, id) in zip(group.tabIDs, group.tabIDs.dropFirst()) {
            placeTab(id, after: previous)
        }
        setSplits(splits)
    }

    /// Épingle (fin de la racine des épinglés) ou désépingle (tête des onglets du jour) tout le split ; sans effet
    /// s'il y est déjà ou vers les favoris.
    mutating func setSplitPlace(_ groupID: UUID, to place: TabPlace) {
        guard let first = split(withID: groupID)?.tabIDs.first, self.place(of: first) != place else {
            return
        }
        switch place {
        case .favorite: return
        case .pinned: moveSplit(groupID, to: .pinned(folder: nil, index: pinned.count))
        case .today: moveSplit(groupID, to: .today(index: 0))
        }
    }

    /// Parts de largeur des panneaux (normalisées ; invalides : parts égales).
    mutating func setSplitFractions(_ groupID: UUID, _ fractions: [Double]) {
        guard let index = splits.firstIndex(where: { $0.id == groupID }) else {
            return
        }
        var groups = splits
        groups[index].setFractions(fractions)
        setSplits(groups)
    }
}
