import SwiftUI

/// Fenêtre de l'historique (⌘Y, menu Historique) : les visites du profil du Space affiché par la fenêtre principale.
/// Une seule fenêtre, ouverte seulement par l'utilisateur, jamais restaurée au lancement.
struct HistoryWindow: View {
    let session: BrowserSession
    @Environment(MiniWindowManager.self) private var miniWindows

    var body: some View {
        if let store = session.history {
            HistoryContent(store: store, session: session, miniWindows: miniWindows)
        }
    }
}

/// Contenu de la fenêtre : son modèle suit le profil montré.
private struct HistoryContent: View {
    let session: BrowserSession
    let miniWindows: MiniWindowManager
    @State private var model: HistoryWindowModel
    @Environment(\.openWindow) private var openWindow

    init(store: HistoryStore, session: BrowserSession, miniWindows: MiniWindowManager) {
        self.session = session
        self.miniWindows = miniWindows
        _model = State(initialValue: HistoryWindowModel(store: store, profileID: miniWindows.historyProfile?.id))
    }

    /// Profil montré.
    private var profile: ProfileRecord? {
        miniWindows.historyProfile
    }

    /// Nom du profil montré quand il y en a plusieurs : sous-titre de la fenêtre et message de l'effacement.
    private var profileName: String? {
        session.profiles.count > 1 ? profile?.name : nil
    }

    var body: some View {
        // Conteneur de navigation : la recherche se place dans la barre d'outils de la fenêtre.
        NavigationStack {
            HistoryView(model: model, faviconService: session.faviconService, profileName: profileName, open: open)
                .navigationTitle(Text("History"))
                .navigationSubtitle(profileName ?? "")
        }
        .onChange(of: profile?.id) { _, id in model.profileID = id }
        .frame(minWidth: 480, minHeight: 320)
    }

    /// Double-clic, Entrée, « Ouvrir dans un nouvel onglet » : chaque ligne dans un nouvel onglet de la fenêtre
    /// principale, qui passe au premier plan (rouverte au besoin, comme « Ouvrir dans le Space »).
    private func open(_ rows: [HistoryRow]) {
        miniWindows.openFromHistory(rows.map(\.url), profileID: model.profileID) {
            openWindow(id: MatchaApp.browserWindowID)
        }
    }
}
