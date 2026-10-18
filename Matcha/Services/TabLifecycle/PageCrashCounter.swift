import Foundation

/// Arrêts récents du processus d'une page (tâche 5.7) : ceux des `window` dernières secondes. Deux arrêts si proches
/// l'un de l'autre font une boucle (la page plante de nouveau juste après son rechargement automatique) :
/// `PageCrashPolicy` cesse alors de la recharger d'elle-même.
nonisolated struct PageCrashCounter: Equatable, Sendable {
    /// Durée pendant laquelle un arrêt compte.
    static let window: TimeInterval = 30

    /// Dates des arrêts encore comptés, du plus ancien au plus récent.
    private(set) var terminations: [Date] = []

    /// Note un arrêt à `date` et renvoie le nombre d'arrêts des `window` dernières secondes, celui-ci compris. Un arrêt
    /// daté après `date` (horloge du système reculée) est oublié.
    mutating func record(at date: Date) -> Int {
        terminations = terminations.filter { (0 ..< Self.window).contains(date.timeIntervalSince($0)) } + [date]
        return terminations.count
    }
}
