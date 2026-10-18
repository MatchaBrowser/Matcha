import Foundation
import WebKit

/// Choix fait dans le menu contextuel d'une page (tâche 5.9), en attente de la fenêtre que WebKit va ouvrir pour lui.
///
/// Aucune API publique ne donne le lien sous le pointeur : un élément de Matcha déclenche l'élément « … dans une
/// nouvelle fenêtre » de WebKit, qui ouvre la fenêtre de façon asynchrone (aller-retour avec le processus de la
/// page) par `createWebViewWith`. Le choix retenu ici dit ce qu'elle devient.
nonisolated struct PageMenuIntent: Equatable, Sendable {
    /// Durée de validité : WebKit répond en quelques millisecondes ; au-delà, une fenêtre vient de la page.
    static let lifetime: TimeInterval = 1

    let destination: PageMenuDestination
    /// Point d'où l'aperçu grandit : le pointeur à l'ouverture du menu, en fractions de la page.
    let openingPoint: CGPoint
    /// Au-delà, le choix est oublié et la fenêtre suit les règles habituelles.
    let deadline: Date
}

/// Ce que l'on sait d'une fenêtre que la page demande (`createWebViewWith`).
nonisolated struct PageMenuWindowRequest: Equatable, Sendable {
    /// `.other` pour la fenêtre de « … dans une nouvelle fenêtre » (vérifié) comme pour `window.open` ;
    /// `.linkActivated` pour un lien `target=_blank`, `.formSubmitted` pour un formulaire.
    var navigationType: WKNavigationType
    /// Vrai si la page donne une taille (fenêtre de connexion, tâche 5.8) : jamais le cas d'une fenêtre du menu.
    var opensPopupWindow: Bool
}

/// Le choix en attente d'une vue web : un seul à la fois, rendu une seule fois, oublié à l'échéance.
nonisolated struct PendingPageMenuIntent: Sendable {
    private(set) var intent: PageMenuIntent?

    /// Retient un choix fait à `now` ; il remplace le précédent.
    mutating func choose(_ destination: PageMenuDestination, openingPoint: CGPoint, at now: Date) {
        intent = PageMenuIntent(
            destination: destination,
            openingPoint: openingPoint,
            deadline: now.addingTimeInterval(PageMenuIntent.lifetime),
        )
    }

    mutating func cancel() {
        intent = nil
    }

    /// Le choix en attente si la fenêtre demandée à `now` peut venir de lui ; il est alors oublié. Un choix échu
    /// est oublié sans être rendu. Une fenêtre qui ne peut pas venir du menu (lien, formulaire, taille donnée) le
    /// laisse en attente : la fenêtre du menu peut encore arriver.
    mutating func take(for request: PageMenuWindowRequest, at now: Date) -> PageMenuIntent? {
        guard let intent else {
            return nil
        }
        guard now <= intent.deadline else {
            self.intent = nil
            return nil
        }
        guard request.navigationType == .other, !request.opensPopupWindow else {
            return nil
        }
        self.intent = nil
        return intent
    }
}
