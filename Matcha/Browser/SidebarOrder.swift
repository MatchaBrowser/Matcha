import Foundation

/// Ordre de la barre latérale vu par le clavier (tâche 4.8) : ce qu'elle montre, de haut en bas. Favoris,
/// puis épinglés (le contenu d'un dossier replié n'est pas montré, il n'y est pas), puis onglets du jour.
/// Un split tient sur une ligne, mais ses panneaux se suivent de gauche à droite dans `tabIDs`. Type pur.
nonisolated struct SidebarOrder: Equatable, Sendable {
    /// Une tuile de favori ou une ligne : un onglet, ou les panneaux d'un split de gauche à droite.
    typealias Item = [UUID]

    /// ⌘1 à ⌘8.
    static let numberedShortcuts = 1 ... 8

    /// Tuiles des favoris, puis lignes des épinglés visibles : celles que numérotent ⌘1 à ⌘8.
    let numbered: [Item]
    /// Lignes des onglets du jour.
    let today: [Item]
    /// Tous les onglets rangés, visibles ou non : situe un onglet sélectionné caché dans un dossier replié.
    private let allTabIDs: [UUID]

    init(_ layout: SidebarLayout) {
        numbered = layout.favorites.map { [$0] } + Self.items(of: layout.pinnedRows(layout.pinned), in: layout)
        today = Self.items(of: layout.todayRows, in: layout)
        allTabIDs = layout.orderedTabIDs
    }

    /// Onglets visibles, de haut en bas ; les panneaux d'un split à la suite.
    var tabIDs: [UUID] {
        (numbered + today).flatMap(\.self)
    }

    /// ⌘1 à ⌘8 : la tuile ou la ligne n° `number` (à partir de 1) des favoris puis des épinglés ; nil au-delà
    /// (les onglets du jour ne sont jamais numérotés).
    func numberedItem(_ number: Int) -> Item? {
        guard Self.numberedShortcuts.contains(number), number <= numbered.count else {
            return nil
        }
        return numbered[number - 1]
    }

    /// ⌘9 : la dernière ligne de la barre (onglets du jour, sinon épinglés, sinon favoris).
    var lastItem: Item? {
        today.last ?? numbered.last
    }

    /// ⌃⇥ (`forward`) et ⌃⇧⇥ : l'onglet visible qui suit (ou précède) `current`, en reprenant au début après
    /// le dernier (et à la fin avant le premier). Dans un split, le panneau voisin vient d'abord. Sans onglet
    /// sélectionné : le premier (ou le dernier). Nil s'il n'y a pas d'autre onglet visible.
    func tab(after current: UUID?, forward: Bool) -> UUID? {
        let visible = tabIDs
        guard let current, let position = allTabIDs.firstIndex(of: current) else {
            return forward ? visible.first : visible.last
        }
        // Parcours de l'ordre complet : un onglet caché (dossier replié) mène à son voisin visible.
        let shown = Set(visible)
        let count = allTabIDs.count
        for step in 1 ..< count {
            let index = (position + (forward ? step : count - step)) % count
            if shown.contains(allTabIDs[index]) {
                return allTabIDs[index]
            }
        }
        return nil
    }

    /// Une entrée par ligne : l'onglet ou les panneaux du split ; un dossier déplié donne ses propres lignes,
    /// à la suite, et un dossier replié aucune.
    private static func items(of rows: [SidebarRow], in layout: SidebarLayout) -> [Item] {
        rows.flatMap { row -> [Item] in
            switch row {
            case let .tab(id, _): [[id]]
            case let .split(group, _): [group.tabIDs]
            case let .folder(folder, _): folder.isCollapsed ? [] : items(of: layout.pinnedRows(folder.items), in: layout)
            }
        }
    }
}
