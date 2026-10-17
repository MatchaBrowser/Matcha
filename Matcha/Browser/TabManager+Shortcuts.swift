import Foundation

/// Raccourcis de la barre latérale (tâche 4.8) : ⌘1 à ⌘8, ⌘9, ⌃⇥ et ⌃⇧⇥, dans l'ordre de `SidebarOrder`.
extension TabManager {
    var sidebarOrder: SidebarOrder {
        SidebarOrder(layout)
    }

    /// Onglet que choisit une tuile ou une ligne : l'onglet, ou le panneau d'un split choisi le plus
    /// récemment (le split revient tel qu'on l'a laissé).
    func target(of item: SidebarOrder.Item) -> BrowserTab? {
        item.compactMap(tab(withID:)).max { $0.lastActivity < $1.lastActivity }
    }

    /// Titre d'une tuile ou d'une ligne : celui de l'onglet, ou ceux des panneaux d'un split.
    func title(of item: SidebarOrder.Item) -> String {
        item.compactMap(tab(withID:)).map(\.displayTitle).formatted(.list(type: .and))
    }

    /// ⌘1 à ⌘8 : la tuile ou la ligne n° `number` des favoris puis des épinglés ; nil au-delà.
    func numberedTab(_ number: Int) -> BrowserTab? {
        sidebarOrder.numberedItem(number).flatMap(target(of:))
    }

    /// ⌘9 : la dernière ligne de la barre.
    var lastSidebarTab: BrowserTab? {
        sidebarOrder.lastItem.flatMap(target(of:))
    }

    /// ⌃⇥ (`forward`) et ⌃⇧⇥ : l'onglet suivant ou précédent de l'onglet sélectionné, en boucle.
    func adjacentTab(forward: Bool) -> BrowserTab? {
        sidebarOrder.tab(after: selectedTabID, forward: forward).flatMap(tab(withID:))
    }
}
