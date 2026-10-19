import Foundation

/// Sidebar shortcuts (task 4.8): ⌘1 to ⌘8, ⌘9, ⌃⇥ and ⌃⇧⇥, in the order of `SidebarOrder`.
extension TabManager {
    var sidebarOrder: SidebarOrder {
        SidebarOrder(layout)
    }

    /// Tab chosen by a tile or a row: the tab, or the most recently chosen pane of a split (the split comes
    /// back as it was left).
    func target(of item: SidebarOrder.Item) -> BrowserTab? {
        item.compactMap(tab(withID:)).max { $0.lastActivity < $1.lastActivity }
    }

    /// Title of a tile or a row: the tab's, or those of a split's panes.
    func title(of item: SidebarOrder.Item) -> String {
        item.compactMap(tab(withID:)).map(\.displayTitle).formatted(.list(type: .and))
    }

    /// ⌘1 to ⌘8: tile or row no. `number` of the favorites then the pinned tabs; nil beyond.
    func numberedTab(_ number: Int) -> BrowserTab? {
        sidebarOrder.numberedItem(number).flatMap(target(of:))
    }

    /// ⌘9: the last row of the sidebar.
    var lastSidebarTab: BrowserTab? {
        sidebarOrder.lastItem.flatMap(target(of:))
    }

    /// ⌃⇥ (`forward`) and ⌃⇧⇥: the tab after or before the selected tab, wrapping around.
    func adjacentTab(forward: Bool) -> BrowserTab? {
        sidebarOrder.tab(after: selectedTabID, forward: forward).flatMap(tab(withID:))
    }
}
