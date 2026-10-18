import Foundation
import Observation
import WebKit

/// Le bloqueur vu d'une session (tâche 6.2) : ses pages lui disent quel document elles vont charger, et ses réglages du
/// site lisent ou changent l'exception d'un site. La session principale lit et écrit les exceptions enregistrées ; une
/// fenêtre privée (ou une base de test) les lit, mais ses changements restent en mémoire et partent avec elle : rien
/// de ce qu'on y visite n'est écrit.
@MainActor
@Observable
final class ContentBlockerScope {
    @ObservationIgnored let service: ContentBlockerService
    /// Faux : les changements d'exception restent dans cette session (`overrides`).
    @ObservationIgnored let savesExceptions: Bool
    /// Exceptions changées dans cette session sans être enregistrées : site → exception (vrai) ou blocage (faux).
    private var overrides: [String: Bool] = [:]

    init(service: ContentBlockerService, savesExceptions: Bool) {
        self.service = service
        self.savesExceptions = savesExceptions
    }

    /// Vrai si le bloqueur est désactivé sur `site` pour les pages de cette session.
    func isExcepted(site: String) -> Bool {
        overrides[site] ?? service.exceptions.contains(site)
    }

    /// Bloque (ou non) sur `site` ; les pages ouvertes de ce site dans les sessions concernées se rechargent.
    func setBlocks(_ blocks: Bool, onSite site: String) {
        guard let site = ContentBlockerExceptions.normalized(site), isExcepted(site: site) == blocks else {
            return
        }
        if savesExceptions {
            service.setException(!blocks, forSite: site)
        } else {
            overrides[site] = !blocks
            service.exceptionsDidChange(forSite: site)
        }
    }

    /// Le document principal de `webView` va être `url` (navigation autorisée, avant son chargement ; ou document
    /// affiché) : les listes y sont posées ou retirées selon son site.
    func prepare(_ webView: WKWebView, for url: URL?) {
        service.prepare(webView, for: url, scope: self)
    }
}
