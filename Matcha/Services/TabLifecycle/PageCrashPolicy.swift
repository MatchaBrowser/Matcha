/// Ce qu'une page fait quand son processus s'arrête (tâche 5.7).
nonisolated enum PageCrashAction: String, Equatable, Sendable {
    /// Page visible : rechargée tout de suite, dans la même vue web (historique précédent/suivant gardé).
    case reload
    /// Page cachée : vue web libérée comme pour une mise en veille (tâche 5.6), recréée quand on l'affiche.
    case reloadWhenShown
    /// Arrêts répétés : plus de rechargement automatique, un message dans la page invite à la recharger.
    case showProblem
}

/// Règles de la reprise d'une page dont le processus s'est arrêté (plantage, ou processus arrêté par le système pour
/// la mémoire ; tâche 5.7). « Visible » : onglet sélectionné ou panneau de son split, dans le Space affiché d'une
/// fenêtre ouverte (notion de la tâche 5.6), page de l'aperçu, page d'une mini-fenêtre.
nonisolated enum PageCrashPolicy {
    /// Rechargements automatiques permis par fenêtre de `PageCrashCounter` : au-delà, la page attend l'utilisateur.
    static let automaticReloads = 1

    /// `recentTerminations` : arrêts des 30 dernières secondes, celui-ci compris (`PageCrashCounter`).
    static func action(isVisible: Bool, recentTerminations: Int) -> PageCrashAction {
        if recentTerminations > automaticReloads {
            return .showProblem
        }
        return isVisible ? .reload : .reloadWhenShown
    }
}
