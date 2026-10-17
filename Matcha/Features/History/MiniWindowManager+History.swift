import Foundation
import OSLog

/// Fenêtre de l'historique (tâche 5.5) : son profil et l'ouverture de ses lignes dans la fenêtre principale. Le
/// gestionnaire des mini-fenêtres tient déjà le lien avec la fenêtre principale et son Space affiché.
extension MiniWindowManager {
    /// Profil dont la fenêtre de l'historique montre les visites : celui du Space affiché par la fenêtre principale
    /// (fermée : le dernier affiché), comme pour une nouvelle mini-fenêtre ; jamais une fenêtre privée.
    var historyProfile: ProfileRecord? {
        displayedSpace.record.profile
    }

    /// Ouvre `urls` dans de nouveaux onglets, en tête des onglets du jour du Space affiché (s'il est du profil
    /// `profileID`, sinon le premier Space de ce profil), dans leur ordre ; le premier est sélectionné. La fenêtre
    /// principale passe au premier plan, rouverte au besoin par `openMainWindow`.
    func openFromHistory(_ urls: [URL], profileID: UUID?, openMainWindow: () -> Void) {
        let space = defaultTarget(profileID: profileID)
        // Chaque nouvel onglet va en tête : le premier est ouvert en dernier.
        let tabs = urls.reversed().map { space.tabManager.newTab(url: $0, select: false) }
        guard let first = tabs.last else {
            return
        }
        space.tabManager.select(first)
        reveal(first, in: space, openMainWindow: openMainWindow)
        Logger.history.info("\(urls.count, privacy: .public) pages ouvertes depuis l'historique")
    }
}
