import Foundation
import WebKit

/// Taille demandée par une page pour la fenêtre qu'elle ouvre (`window.open(url, nom, "width=500,height=600")`, tâche
/// 5.8), en points, pour la page elle-même (sans barre de titre). Une valeur absente, nulle, négative ou non finie
/// ne compte pas : WebKit prend alors la taille par défaut. La position demandée (`left`, `top`) n'est pas gardée :
/// `DECISIONS.md`.
nonisolated struct PopupWindowFeatures: Equatable, Sendable {
    let width: Double?
    let height: Double?

    init(width: Double? = nil, height: Double? = nil) {
        self.width = Self.dimension(width)
        self.height = Self.dimension(height)
    }

    /// Vrai si la page donne une taille : fenêtre de connexion (Google, Apple, banque, paiement) dans sa propre
    /// fenêtre. Sinon (lien `target=_blank`, `window.open` sans taille), un onglet, comme avant.
    var opensPopupWindow: Bool {
        width != nil || height != nil
    }

    private static func dimension(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else {
            return nil
        }
        return value
    }
}

extension PopupWindowFeatures {
    /// Ce que WebKit transmet de la chaîne de `window.open` (vérifié : chaque valeur n'est donnée que si la page l'écrit).
    @MainActor
    init(_ features: WKWindowFeatures) {
        self.init(width: features.width?.doubleValue, height: features.height?.doubleValue)
    }
}
