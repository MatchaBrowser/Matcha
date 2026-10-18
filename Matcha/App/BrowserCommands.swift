import AppKit
import SwiftUI

/// Commandes de menu et raccourcis clavier du navigateur, appliqués à la fenêtre active : une mini-fenêtre
/// (toujours regardée d'abord : les valeurs de fenêtre sont nil quand un panneau est actif), sinon la fenêtre
/// de navigation.
struct BrowserCommands: Commands {
    let miniWindows: MiniWindowManager
    @FocusedValue(\.tabManager) private var tabManager
    @FocusedValue(\.windowActions) private var windowActions
    @Environment(\.openWindow) private var openWindow

    /// Mini-fenêtre active : `keyWindowID` est lu pour que le menu suive, la fenêtre est relue à chaque action.
    private var miniWindow: MiniWindowController? {
        _ = miniWindows.keyWindowID
        return miniWindows.keyWindow
    }

    private var selectedTab: BrowserTab? {
        tabManager?.selectedTab
    }

    /// Page au premier plan : celle de la mini-fenêtre active, l'aperçu s'il est ouvert, sinon l'onglet sélectionné.
    private var frontTab: BrowserTab? {
        miniWindow?.tab ?? tabManager?.frontTab
    }

    /// Aperçu ouvert (et pas de barre de commande) : ⌘W le ferme.
    private var isPeekOpen: Bool {
        tabManager?.peek != nil && windowActions?.isCommandBarPresented != true
    }

    private var closeTitle: Text {
        if miniWindow != nil {
            Text("Close Mini Window")
        } else if isPeekOpen {
            Text(PeekActions.closeTitle)
        } else {
            Text("Close Tab")
        }
    }

    private var sidebarToggleTitle: LocalizedStringKey {
        windowActions?.isSidebarVisible == false ? "Show Sidebar" : "Hide Sidebar"
    }

    private var downloadsToggleTitle: LocalizedStringKey {
        windowActions?.isDownloadsPanelShown == true ? "Hide Downloads" : "Show Downloads"
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                if let mini = miniWindow {
                    // Une mini-fenêtre n'a qu'une page : une nouvelle recherche la remplace.
                    mini.showCommandBar(.newSearch)
                } else {
                    windowActions?.newTab()
                }
            }
            .keyboardShortcut("t")
            .disabled(windowActions == nil && miniWindow == nil)

            Button("New Private Window") {
                openWindow(id: MatchaApp.privateWindowID)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            // Sans équivalent clavier : le raccourci global (réglable) l'est déjà, et un raccourci affiché ici
            // se déclencherait deux fois, menu ouvert.
            Button("New Mini Window") {
                miniWindows.openNew(source: .menu)
            }

            Button("Open Location…") {
                if let mini = miniWindow {
                    mini.showCommandBar(.editAddress)
                } else {
                    windowActions?.editAddress()
                }
            }
            .keyboardShortcut("l")
            .disabled(windowActions == nil && miniWindow == nil)

            Button("Open in Space") {
                if let mini = miniWindow {
                    miniWindows.openInSpace(mini) { openWindow(id: MatchaApp.browserWindowID) }
                }
            }
            .keyboardShortcut("o")
            .disabled(miniWindow?.tab.hasURL != true)
        }

        // Remplace « Fermer » (⌘W) : ⌘W ferme l'onglet (ou l'aperçu, ou la mini-fenêtre), ⇧⌘W la fenêtre,
        // comme dans Safari.
        CommandGroup(replacing: .saveItem) {
            Button(action: closeCommand) {
                closeTitle
            }
            .keyboardShortcut("w")
            .disabled(miniWindow == nil && tabManager != nil && selectedTab == nil && windowActions?.isCommandBarPresented != true)

            Button("Close Window") {
                if let mini = miniWindow {
                    mini.close()
                } else {
                    NSApp.keyWindow?.performClose(nil)
                }
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        // Dans le menu Édition, juste après Copier, Coller, etc.
        CommandGroup(after: .pasteboard) {
            // Même titre que l'action de la barre de commande.
            Button(CommandActionID.copyURL.title) {
                if let mini = miniWindow {
                    mini.copyURL()
                } else {
                    windowActions?.copyURL?()
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(miniWindow.map { !$0.tab.hasURL } ?? (windowActions?.copyURL == nil))
        }

        // Édition > Rechercher (⌘F, ⌘G, ⇧⌘G).
        FindCommands(miniWindows: miniWindows)

        CommandGroup(replacing: .sidebar) {
            Button(sidebarToggleTitle) {
                windowActions?.toggleSidebar()
            }
            .keyboardShortcut("s")
            .disabled(windowActions == nil)

            // Présentation > « Afficher les téléchargements » (⌥⌘L), comme dans Safari. Grisé hors d'une fenêtre de
            // navigation (Réglages, historique) et quand une mini-fenêtre est active : elle n'a pas de barre latérale.
            Button(downloadsToggleTitle) {
                windowActions?.toggleDownloads()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(windowActions == nil || miniWindow != nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Reload Page") { frontTab?.reload() }
                .keyboardShortcut("r")
                .disabled(frontTab?.hasURL != true)
        }

        // Fichier > Exporter en PDF…, Imprimer… ; Présentation > zoom (tâche 5.4), après « Recharger la page ».
        PageCommands(miniWindows: miniWindows)

        CommandMenu("Spaces") {
            if let windowActions {
                ForEach(Array(windowActions.spaceNames.prefix(9).enumerated()), id: \.offset) { index, name in
                    Button(name) { windowActions.selectSpace(index) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .control)
                }
                Divider()
                Button("New Space") { windowActions.newSpace() }
            }
        }

        // Menu Onglets : juste après Spaces.
        TabCommands(miniWindows: miniWindows)

        // Menu Historique : Accueil, Précédent, Suivant, « Afficher tout l'historique » (tâche 5.5).
        HistoryCommands(miniWindows: miniWindows)
    }

    /// ⌘W : la mini-fenêtre active (sa barre d'abord), sinon la barre de commande, l'aperçu, l'onglet, ou la
    /// fenêtre sans onglets (réglages).
    private func closeCommand() {
        if let mini = miniWindow {
            mini.closeCommand()
        } else if let windowActions, windowActions.isCommandBarPresented {
            // Barre de commande ouverte : ⌘W ne ferme qu'elle, jamais l'onglet par réflexe.
            windowActions.closeCommandBar()
        } else if let tabManager, tabManager.peek != nil {
            // Aperçu ouvert : ⌘W ne ferme que lui.
            PeekActions.close(in: tabManager)
        } else if let tabManager {
            if let tab = tabManager.selectedTab {
                tabManager.close(tab)
            }
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }
}
