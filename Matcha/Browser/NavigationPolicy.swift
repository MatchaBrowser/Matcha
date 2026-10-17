import AppKit
import WebKit

/// Ce qu'il faut savoir d'une demande de navigation pour décider quoi en faire.
nonisolated struct NavigationRequest: Sendable {
    var url: URL?
    var navigationType: WKNavigationType
    var modifierFlags: NSEvent.ModifierFlags
    /// Bouton de la souris : 0 gauche, 1 droit, 2 milieu (molette), -1 aucun.
    var buttonNumber: Int
    /// Vrai si la navigation vise le cadre principal ou une nouvelle fenêtre, faux pour un cadre secondaire.
    var targetsMainFrame: Bool
    /// Vrai si la vue web sait charger ce schéma (http, https, about, data, blob, schéma enregistré…).
    var isSchemeHandledByWebView: Bool
}

/// Issue d'une demande de navigation.
nonisolated enum NavigationDecision: Equatable, Sendable {
    /// WebKit poursuit la navigation.
    case allow
    /// La navigation est annulée sans autre effet.
    case cancel
    /// Annulée, puis l'URL est confiée à l'app qui la gère (Mail, Téléphone, Zoom…).
    case openExternally(URL)
    /// Annulée, puis l'URL est ouverte dans un nouvel onglet.
    case openInNewTab(URL, inBackground: Bool)
}

/// Règles de navigation des vues web, sans dépendance à l'interface.
nonisolated enum NavigationPolicy {
    static let middleMouseButton = 2

    static func decide(_ request: NavigationRequest) -> NavigationDecision {
        guard let url = request.url else {
            return .allow
        }
        if !request.isSchemeHandledByWebView {
            // Un cadre secondaire (publicité…) n'a pas le droit de lancer une autre app.
            return request.targetsMainFrame ? .openExternally(url) : .cancel
        }
        let isModifiedClick = request.modifierFlags.contains(.command) || request.buttonNumber == middleMouseButton
        if request.navigationType == .linkActivated, isModifiedClick {
            return .openInNewTab(url, inBackground: !request.modifierFlags.contains(.shift))
        }
        return .allow
    }
}
