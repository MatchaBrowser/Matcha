import Foundation

/// Depuis quand chaque onglet est caché (tâche 5.6). « Visible » : affiché dans une fenêtre ouverte, onglet
/// sélectionné ou panneau de son split, dans le Space affiché ; le reste est caché, y compris l'onglet sélectionné d'un
/// Space qui n'est pas affiché. Mis à jour à chaque changement de ce qui est affiché, avec l'heure du changement.
nonisolated struct TabVisibilityTracker: Sendable {
    /// Onglets cachés et l'heure à laquelle ils ont quitté l'écran (ou ont été vus cachés la première fois).
    private(set) var hiddenSince: [UUID: Date] = [:]

    /// `visible` : onglets affichés ; `present` : tous les onglets ouverts. Un onglet qui quitte l'écran est caché depuis
    /// `now` ; un onglet caché garde sa date ; un onglet fermé est oublié.
    mutating func update(visible: Set<UUID>, present: Set<UUID>, now: Date) {
        var next: [UUID: Date] = [:]
        for id in present where !visible.contains(id) {
            next[id] = hiddenSince[id] ?? now
        }
        hiddenSince = next
    }

    func hiddenSince(_ id: UUID) -> Date? {
        hiddenSince[id]
    }
}
