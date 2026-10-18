import Foundation

/// Un onglet ouvert, tel que le voit la mise en veille.
nonisolated struct TabLifecycleCandidate: Equatable, Sendable {
    let id: UUID
    /// Moment où l'onglet a quitté l'écran ; nil s'il est affiché.
    let hiddenSince: Date?
    /// Vue web présente : sinon il n'y a rien à libérer (onglet jamais affiché depuis le lancement, déjà en veille).
    let isLoaded: Bool
    /// Bandeau de permission en attente d'une réponse (tâche 5.2).
    let hasPendingPermissionPrompt: Bool
    /// Caméra ou micro en cours d'utilisation (même coupés).
    let isCapturingMedia: Bool
    /// Fenêtre de connexion ouverte par la page, encore ouverte (tâche 5.8) : en veille, la page ne serait plus son
    /// `window.opener`, et la connexion échouerait.
    let hasOpenPopupWindow: Bool
}

/// Ce qui déclenche une vérification.
nonisolated enum TabSuspensionReason: String, Sendable {
    /// Vérification régulière : onglets cachés depuis plus que le délai réglé.
    case inactivity
    /// Alerte mémoire du système : la moitié la plus ancienne des onglets cachés.
    case memoryWarning
    /// Alerte mémoire critique : tous les onglets cachés.
    case memoryCritical
}

/// Règles de la mise en veille (tâche 5.6). Jamais : un onglet affiché (tous les panneaux d'un split, l'onglet d'origine
/// d'un aperçu), sans vue web, qui attend une réponse de permission, qui utilise la caméra ou le micro, qui a ouvert
/// une fenêtre de connexion encore ouverte (tâche 5.8), ou qui joue du son (vérifié ensuite, auprès de WebKit).
/// « Jamais » dans les réglages : rien, même pendant une alerte mémoire.
nonisolated enum TabSuspensionPolicy {
    /// Pendant une alerte simple, un onglet caché depuis moins longtemps est épargné : on revient souvent à l'onglet
    /// qu'on vient de quitter.
    static let warningMinimumHiddenTime: TimeInterval = 60

    static func isEligible(_ candidate: TabLifecycleCandidate) -> Bool {
        candidate.hiddenSince != nil && candidate.isLoaded && !candidate.hasPendingPermissionPrompt && !candidate.isCapturingMedia
            && !candidate.hasOpenPopupWindow
    }

    /// Onglets à examiner, du plus anciennement caché au plus récent ; `delay` nil (« Jamais ») : aucun. Le son se
    /// vérifie ensuite, sur ces onglets seulement.
    static func pool(_ candidates: [TabLifecycleCandidate], reason: TabSuspensionReason, delay: TimeInterval?, now: Date) -> [UUID] {
        guard let delay else {
            return []
        }
        let minimumHiddenTime: TimeInterval? = switch reason {
        case .inactivity: delay
        case .memoryWarning: warningMinimumHiddenTime
        case .memoryCritical: nil
        }
        return candidates
            .compactMap { candidate -> (id: UUID, hiddenSince: Date)? in
                guard isEligible(candidate), let hiddenSince = candidate.hiddenSince else {
                    return nil
                }
                if let minimumHiddenTime, now.timeIntervalSince(hiddenSince) < minimumHiddenTime {
                    return nil
                }
                return (candidate.id, hiddenSince)
            }
            .sorted { ($0.hiddenSince, $0.id.uuidString) < ($1.hiddenSince, $1.id.uuidString) }
            .map(\.id)
    }

    /// Parmi les onglets examinés qui ne jouent pas de son (dans l'ordre de `pool`), ceux à mettre en veille : la
    /// moitié la plus ancienne (arrondie au-dessus) pendant une alerte simple, sinon tous.
    static func limit(_ idle: [UUID], reason: TabSuspensionReason) -> [UUID] {
        reason == .memoryWarning ? Array(idle.prefix((idle.count + 1) / 2)) : idle
    }
}

nonisolated extension Duration {
    /// Durée en secondes, pour les comparaisons de dates.
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
