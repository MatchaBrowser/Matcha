import Foundation
import OSLog
import WebKit

/// Recherche dans la page de l'onglet (tâche 5.3), par l'API publique de WebKit : `find(_:configuration:)` dit
/// seulement si une occurrence existe (`WKFindResult.matchFound`), sans leur nombre ; l'occurrence trouvée devient
/// la sélection de la page, qui défile jusqu'à elle.
extension BrowserTab: FindPerformer {
    /// Désélectionne, dans un monde JavaScript séparé que la page ne peut pas modifier. Cadre principal seulement :
    /// une occurrence trouvée dans un cadre intégré reste sélectionnée.
    static let deselectScript = "window.getSelection().removeAllRanges(); true"

    func search(_ query: String, direction: FindDirection) async -> Bool? {
        guard let webView else {
            return nil
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = direction == .backward
        configuration.caseSensitive = false
        configuration.wraps = true
        do {
            return try await webView.find(query, configuration: configuration).matchFound
        } catch {
            // Jamais le texte cherché.
            Logger.browser.error("Recherche dans la page impossible : \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }

    func deselectMatch() {
        webView?.evaluateJavaScript(Self.deselectScript, in: nil, in: .defaultClient)
    }
}
