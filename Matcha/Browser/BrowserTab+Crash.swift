import Foundation

/// Arrêt du processus de la page (tâche 5.7) : ce qu'en fait l'onglet, d'après la décision de `PageCrashPolicy`.
extension BrowserTab {
    /// Sortie de veille (tâche 5.6) ou reprise après un arrêt du processus (5.7) : un titre vide ou une adresse absente
    /// de la vue web ne remplacent pas ceux de l'onglet.
    var keepsTitleAndAddress: Bool {
        suspension.isRestoring || crash.isRecovering
    }

    /// Appelé pendant que WebKit prévient le délégué : la vue web a encore son adresse, son titre et son état de
    /// navigation. Les demandes de permission en attente sont refusées et la recherche dans la page oubliée (il n'y a
    /// plus de page) ; zoom, icône, titre et adresse restent.
    func webContentProcessDidTerminate(_ action: PageCrashAction) {
        permissionPrompts.denyAll()
        find.pageDidTerminate()
        switch action {
        case .reload:
            // Au tour suivant de la boucle principale : WebKit finit d'abord de traiter l'arrêt (il efface l'adresse et
            // le titre de la vue). Vérifié : `reload()` relance un processus et recharge la page en cours de la même
            // vue web, historique précédent/suivant et zoom compris.
            let terminated = webView
            Task { [weak self] in
                guard let self, let terminated, webView === terminated, crash.isRecovering else {
                    return
                }
                reload()
            }
        case .reloadWhenShown:
            // Comme une mise en veille (tâche 5.6), sans capture : l'état de navigation est encore lisible, la vue
            // morte est libérée et la page revient, avec son historique, quand on affiche l'onglet.
            suspend(snapshot: nil)
        case .showProblem:
            crash.showProblem()
        }
    }
}
