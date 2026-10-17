import Foundation

/// Ce qu'affiche un nouvel onglet.
nonisolated enum NewTabPage: String, CaseIterable, Identifiable, Sendable {
    /// Onglet vide, curseur dans la barre d'adresse.
    case blank
    /// Page d'accueil des réglages.
    case homePage

    var id: Self {
        self
    }

    var title: LocalizedStringResource {
        switch self {
        case .blank: LocalizedStringResource("Empty Page", comment: "Option of “New tabs open with”")
        case .homePage: LocalizedStringResource("Your Homepage", comment: "Option of “New tabs open with”")
        }
    }
}
