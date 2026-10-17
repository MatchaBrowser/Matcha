import AppKit
import SwiftUI

@main
struct MatchaApp: App {
    static let browserWindowID = "browser"
    static let privateWindowID = "private"
    static let historyWindowID = "history"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(BrowserSettings.Key.appearance) private var appearance = BrowserSettings.appearance
    @State private var session: BrowserSession
    /// Mini-fenêtres de toute l'app (tâche 4.5).
    @State private var miniWindows: MiniWindowManager

    init() {
        // Les onglets sont les nôtres : pas d'onglets de fenêtre macOS (« Afficher la barre d'onglets »).
        NSWindow.allowsAutomaticWindowTabbing = false
        // Tests d'interface : leur dossier de téléchargements repart vide (sans effet sinon).
        DownloadLocation.resetTestSubfolderIfRequested()
        let session = BrowserSession.launch()
        // Historique lu dès le lancement, hors du fil principal, après l'effacement des visites de plus d'un an : la
        // barre de commande le trouve prêt.
        if let history = session.history {
            Task { await history.load() }
        }
        // Rien n'est retenu (taille, Space affiché) avec une base de test.
        let miniWindows = MiniWindowManager(session: session, defaults: session.isInMemory ? nil : .standard)
        // Raccourci global de la mini-fenêtre, sauf dans l'app hôte des tests unitaires : il serait pris à
        // l'utilisateur, et son premier accès écrirait ⌥⌘N dans ses réglages (même identifiant d'app).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            miniWindows.start()
        }
        _session = State(initialValue: session)
        _miniWindows = State(initialValue: miniWindows)
    }

    var body: some Scene {
        // Une seule fenêtre principale tant que le partage des Spaces entre fenêtres n'est pas défini.
        Window(Text(verbatim: "Matcha"), id: Self.browserWindowID) {
            BrowserWindowView(session: session)
                .environment(miniWindows)
                .environment(DownloadManager.shared)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            BrowserCommands(miniWindows: miniWindows)
        }
        .onChange(of: appearance, initial: true) { appearance.apply() }

        // Fenêtres privées : chacune a sa session en mémoire, rien n'est enregistré.
        WindowGroup("Private Browsing", id: Self.privateWindowID) {
            PrivateWindowView()
                .environment(DownloadManager.shared)
        }
        .windowStyle(.hiddenTitleBar)
        // Sans ses commandes par défaut (« Close », « Close All ») qui écraseraient ⌘W et ⇧⌘W.
        .commandsRemoved()

        // Historique (⌘Y, tâche 5.5) : une seule fenêtre, ouverte seulement par l'utilisateur, jamais au lancement ni
        // restaurée ; sans commandes à elle (pas d'élément en plus dans le menu Fenêtre).
        Window(Text("History"), id: Self.historyWindowID) {
            HistoryWindow(session: session)
                .environment(miniWindows)
        }
        .defaultSize(width: 760, height: 560)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        Settings {
            SettingsView()
                .environment(session)
                .environment(miniWindows)
        }
    }
}
