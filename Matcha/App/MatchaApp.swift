import AppKit
import SwiftUI

@main
struct MatchaApp: App {
    static let privateWindowID = "private"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(BrowserSettings.Key.appearance) private var appearance = BrowserSettings.appearance
    @State private var session = BrowserSession.launch()

    init() {
        // Les onglets sont les nôtres : pas d'onglets de fenêtre macOS (« Afficher la barre d'onglets »).
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        // Une seule fenêtre principale tant que le partage des Spaces entre fenêtres n'est pas défini.
        Window(Text(verbatim: "Matcha"), id: "browser") {
            BrowserWindowView(session: session)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            BrowserCommands()
        }
        .onChange(of: appearance, initial: true) { appearance.apply() }

        // Fenêtres privées : chacune a sa session en mémoire, rien n'est enregistré.
        WindowGroup("Private Browsing", id: Self.privateWindowID) {
            PrivateWindowView()
        }
        .windowStyle(.hiddenTitleBar)
        // Sans ses commandes par défaut (« Close », « Close All ») qui écraseraient ⌘W et ⇧⌘W.
        .commandsRemoved()

        Settings {
            SettingsView()
                .environment(session)
        }
    }
}
