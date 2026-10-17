import SwiftUI

/// Menu Onglets (tâche 4.8), après le menu Spaces comme dans Arc : ⌃⇥ et ⌃⇧⇥ parcourent les onglets dans
/// l'ordre de la barre latérale, en boucle ; ⌘1 à ⌘8 choisissent les premiers favoris puis épinglés (listés
/// sous leur titre, comme les Spaces) ; ⌘9 le dernier onglet. Inactif quand une mini-fenêtre est active, ou
/// sans fenêtre de navigation active (Réglages).
struct TabCommands: Commands {
    let miniWindows: MiniWindowManager
    @FocusedValue(\.tabManager) private var focusedTabManager
    @FocusedValue(\.windowActions) private var windowActions

    /// Onglets de la fenêtre de navigation active ; nil quand une mini-fenêtre est active (`keyWindowID` est lu
    /// pour que le menu suive, la fenêtre est relue à chaque action).
    private var tabManager: TabManager? {
        _ = miniWindows.keyWindowID
        return miniWindows.keyWindow == nil ? focusedTabManager : nil
    }

    var body: some Commands {
        CommandMenu("Tabs") {
            let tabManager = tabManager
            Button("Show Next Tab") { show(self.tabManager?.adjacentTab(forward: true)) }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled(tabManager?.adjacentTab(forward: true) == nil)
            Button("Show Previous Tab") { show(self.tabManager?.adjacentTab(forward: false)) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(tabManager?.adjacentTab(forward: false) == nil)
            if let tabManager {
                let order = tabManager.sidebarOrder
                Divider()
                ForEach(Array(order.numbered.prefix(SidebarOrder.numberedShortcuts.count).enumerated()), id: \.offset) { index, item in
                    Button(tabManager.title(of: item)) { show(self.tabManager?.numberedTab(index + 1)) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
                Button("Show Last Tab") { show(self.tabManager?.lastSidebarTab) }
                    .keyboardShortcut("9")
                    .disabled(order.lastItem == nil)
            }
        }
    }

    private func show(_ tab: BrowserTab?) {
        if let tab {
            windowActions?.showTab(tab)
        }
    }
}
