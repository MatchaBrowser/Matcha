import SwiftUI

/// Éléments « split view » du menu contextuel d'un onglet : l'ouvrir à côté du panneau actif (grisé quand
/// le split affiché est plein, absent quand c'est impossible), le retirer de son split ou défaire celui-ci.
struct SplitMenuItems: View {
    let tab: BrowserTab
    let tabManager: TabManager

    var body: some View {
        let availability = tabManager.splitAvailability(for: tab.id)
        let group = tabManager.split(containing: tab)
        if availability != .unavailable {
            Button("Open in Split View") {
                if tabManager.openInSplit(tab) {
                    TabActivation.activate(tab, in: tabManager)
                }
            }
            .disabled(availability == .full)
        }
        if let group {
            Button("Remove from Split View") { tabManager.removeFromSplit(tab) }
            Button("Separate Tabs") { tabManager.separateSplit(group.id) }
        }
        if availability != .unavailable || group != nil {
            Divider()
        }
    }
}
