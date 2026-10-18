import Foundation

/// Réglage « Libérer la mémoire des onglets inactifs après » (tâche 5.6) : durée après laquelle un onglet caché est mis
/// en veille. Valeur enregistrée : le nombre de minutes, 0 pour « Jamais ».
nonisolated enum TabSuspensionDelay: Int, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    /// Aucune mise en veille automatique, ni après le délai ni pendant une alerte mémoire.
    case never = 0

    var id: Self {
        self
    }

    /// Durée avant la mise en veille ; nil pour « Jamais ».
    var duration: Duration? {
        self == .never ? nil : .seconds(rawValue * 60)
    }

    var title: LocalizedStringResource {
        switch self {
        case .fifteenMinutes: LocalizedStringResource("15 minutes", comment: "Option of “Free memory of inactive tabs after”")
        case .thirtyMinutes: LocalizedStringResource("30 minutes", comment: "Option of “Free memory of inactive tabs after”")
        case .oneHour: LocalizedStringResource("1 hour", comment: "Option of “Free memory of inactive tabs after”")
        case .twoHours: LocalizedStringResource("2 hours", comment: "Option of “Free memory of inactive tabs after”")
        case .never: LocalizedStringResource("Never", comment: "Option of “Free memory of inactive tabs after”")
        }
    }
}
