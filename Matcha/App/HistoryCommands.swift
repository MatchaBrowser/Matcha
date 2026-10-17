import SwiftUI

/// Menu Historique : page d'accueil, précédent et suivant de la page au premier plan, et la fenêtre de l'historique
/// (⌘Y, tâche 5.5), grisée quand une fenêtre privée est active (elle n'a pas d'historique).
struct HistoryCommands: Commands {
    let miniWindows: MiniWindowManager
    @FocusedValue(\.tabManager) private var tabManager
    @FocusedValue(\.windowActions) private var windowActions
    @Environment(\.openWindow) private var openWindow

    /// Page au premier plan : celle de la mini-fenêtre active, l'aperçu s'il est ouvert, sinon l'onglet sélectionné.
    private var frontTab: BrowserTab? {
        _ = miniWindows.keyWindowID
        return miniWindows.keyWindow?.tab ?? tabManager?.frontTab
    }

    var body: some Commands {
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
            Divider()
            Button("Show All History") { openWindow(id: MatchaApp.historyWindowID) }
                .keyboardShortcut("y")
                .disabled(windowActions?.isPrivate == true)
        }
    }
}
