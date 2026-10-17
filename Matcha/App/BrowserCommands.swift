import AppKit
import SwiftUI

/// Commandes de menu et raccourcis clavier du navigateur, appliqués à la fenêtre active.
struct BrowserCommands: Commands {
    @FocusedValue(\.tabManager) private var tabManager
    @FocusedValue(\.windowActions) private var windowActions
    @Environment(\.openWindow) private var openWindow

    private var selectedTab: BrowserTab? {
        tabManager?.selectedTab
    }

    /// Page au premier plan : l'aperçu s'il est ouvert, sinon l'onglet sélectionné.
    private var frontTab: BrowserTab? {
        tabManager?.frontTab
    }

    /// Aperçu ouvert (et pas de barre de commande) : ⌘W le ferme.
    private var isPeekOpen: Bool {
        tabManager?.peek != nil && windowActions?.isCommandBarPresented != true
    }

    private var sidebarToggleTitle: LocalizedStringKey {
        windowActions?.isSidebarVisible == false ? "Show Sidebar" : "Hide Sidebar"
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                windowActions?.newTab()
            }
            .keyboardShortcut("t")
            .disabled(windowActions == nil)

            Button("New Private Window") {
                openWindow(id: MatchaApp.privateWindowID)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open Location…") {
                windowActions?.editAddress()
            }
            .keyboardShortcut("l")
            .disabled(windowActions == nil)
        }

        // Remplace « Fermer » (⌘W) : ⌘W ferme l'onglet (ou l'aperçu), ⇧⌘W la fenêtre, comme dans Safari.
        CommandGroup(replacing: .saveItem) {
            Button {
                if let windowActions, windowActions.isCommandBarPresented {
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
                    // Fenêtre sans onglets (réglages) : ⌘W la ferme.
                    NSApp.keyWindow?.performClose(nil)
                }
            } label: {
                isPeekOpen ? Text(PeekActions.closeTitle) : Text("Close Tab")
            }
            .keyboardShortcut("w")
            .disabled(tabManager != nil && selectedTab == nil && windowActions?.isCommandBarPresented != true)

            Button("Close Window") {
                NSApp.keyWindow?.performClose(nil)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        // Dans le menu Édition, juste après Copier, Coller, etc.
        CommandGroup(after: .pasteboard) {
            // Même titre que l'action de la barre de commande.
            Button(CommandActionID.copyURL.title) { windowActions?.copyURL?() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(windowActions?.copyURL == nil)
        }

        CommandGroup(replacing: .sidebar) {
            Button(sidebarToggleTitle) {
                windowActions?.toggleSidebar()
            }
            .keyboardShortcut("s")
            .disabled(windowActions == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Reload Page") { frontTab?.reload() }
                .keyboardShortcut("r")
                .disabled(frontTab?.hasURL != true)
        }

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

        CommandMenu("History") {
            Button("Homepage") { windowActions?.goHome?() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(windowActions?.goHome == nil)
            Divider()
            Button("Back") { frontTab?.goBack() }
                .keyboardShortcut("[")
                .disabled(frontTab?.canGoBack != true)
            Button("Forward") { frontTab?.goForward() }
                .keyboardShortcut("]")
                .disabled(frontTab?.canGoForward != true)
        }
    }
}
