import Foundation
import WebKit

/// Outils pour développeurs web (réglage « Afficher les fonctions pour les développeurs web », Réglages > Avancé) :
/// « Inspecter l'élément » dans le menu des pages ouvre l'inspecteur web dans Matcha, et pages et extensions sont aussi
/// inspectables depuis le menu Développement de Safari. Désactivés par défaut (activés en Debug), suivis aussitôt par
/// les pages ouvertes (`didChange`).
///
/// Exception à la règle des API publiques, voulue par l'utilisateur (`DECISIONS.md`, 2026-10-18) : WebKit n'offre
/// l'inspecteur dans l'app que par sa préférence privée `developerExtrasEnabled`. Elle n'est posée que si `WKPreferences`
/// la connaît encore ; sinon, rien ne casse et seule l'inspection depuis Safari (`isInspectable`, public) reste.
@MainActor
enum WebInspection {
    /// Le réglage a changé : les vues web le reprennent.
    static let didChange = Notification.Name("MatchaWebInspectionDidChange")

    /// Accesseur privé de WebKit derrière la clé `developerExtrasEnabled`.
    private static let developerExtrasSetter = NSSelectorFromString("_setDeveloperExtrasEnabled:")

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: BrowserSettings.Key.showsDeveloperTools) == nil
            ? BrowserSettings.showsDeveloperTools
            : defaults.bool(forKey: BrowserSettings.Key.showsDeveloperTools)
    }

    /// Vrai si ce WebKit permet l'inspecteur dans l'app.
    static var offersInAppInspector: Bool {
        WKPreferences().responds(to: developerExtrasSetter)
    }

    static func apply(to webView: WKWebView, enabled: Bool = isEnabled()) {
        webView.isInspectable = enabled
        apply(to: webView.configuration.preferences, enabled: enabled)
    }

    static func apply(to preferences: WKPreferences, enabled: Bool = isEnabled()) {
        guard preferences.responds(to: developerExtrasSetter) else {
            return
        }
        preferences.setValue(enabled, forKey: "developerExtrasEnabled")
    }
}
