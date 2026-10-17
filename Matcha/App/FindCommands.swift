import SwiftUI

/// Sous-menu Édition > Rechercher (tâche 5.3), comme dans Safari : « Rechercher… » (⌘F), « Rechercher le suivant »
/// (⌘G), « Rechercher le précédent » (⇧⌘G), sur la page de la fenêtre active (`FindTarget`). Il prend la place des
/// commandes de recherche standard (`.textEditing`, vide aujourd'hui) : jamais deux ⌘F. Une page qui garde ⌘F ou ⌘G
/// pour elle (éditeur en ligne) passe avant, comme dans Safari : WebKit lui envoie les raccourcis d'abord.
struct FindCommands: Commands {
    let miniWindows: MiniWindowManager
    @FocusedValue(\.tabManager) private var tabManager
    @FocusedValue(\.windowActions) private var windowActions

    /// Mini-fenêtre active : `keyWindowID` est lu pour que le menu suive, la fenêtre est relue à chaque action.
    private var miniWindow: MiniWindowController? {
        _ = miniWindows.keyWindowID
        return miniWindows.keyWindow
    }

    private var page: BrowserTab? {
        FindTarget.page(miniWindowTab: miniWindow?.tab, tabManager: tabManager)
    }

    var body: some Commands {
        CommandGroup(replacing: .textEditing) {
            Menu("Find") {
                let page = page
                Button("Find…", action: showFindBar)
                    .keyboardShortcut("f")
                    .disabled(page == nil)
                // ⌘G et ⇧⌘G rouvrent la barre fermée, sans lui donner le clavier.
                Button("Find Next") { self.page?.find.findNext() }
                    .keyboardShortcut("g")
                    .disabled(page?.find.hasQuery != true)
                Button("Find Previous") { self.page?.find.findPrevious() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(page?.find.hasQuery != true)
            }
        }
    }

    /// ⌘F : la barre de commande ouverte se ferme d'abord (une seule saisie à la fois), puis la barre de recherche
    /// s'ouvre, ou reste ouverte, et son champ prend le clavier, texte sélectionné.
    private func showFindBar() {
        guard let page else {
            return
        }
        if let mini = miniWindow {
            if mini.commandBar.isPresented {
                mini.cancelCommandBar()
            }
        } else if let windowActions, windowActions.isCommandBarPresented {
            windowActions.closeCommandBar()
        }
        page.find.present()
    }
}
