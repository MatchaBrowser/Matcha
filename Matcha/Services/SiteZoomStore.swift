import Foundation
import Observation
import OSLog

/// Zoom des pages retenu par site (tâche 5.4), pour tous les profils : un réglage de lecture, comme la taille du texte,
/// pas une donnée du site. Chaque nouveau document d'une page (onglet, aperçu, mini-fenêtre) prend le zoom de son site
/// (`pageDidCommit`) ; un changement s'applique aussitôt à toutes les pages ouvertes de ce site, comme dans Safari.
/// 100 % n'est pas retenu. Enregistré dans les réglages de l'app (`siteZoomLevels`) ; sans `defaults` (fenêtre privée,
/// base de test), tout reste en mémoire et part avec la session.
@MainActor
@Observable
final class SiteZoomStore {
    /// Réglage de l'app : site → zoom (1.25 pour 125 %).
    static let defaultsKey = "siteZoomLevels"

    /// Zoom de chaque site qui n'est pas à 100 %.
    private(set) var levels: [String: Double]
    @ObservationIgnored private let defaults: UserDefaults?
    /// Pages ouvertes et site de leur document affiché, pour leur appliquer un changement du zoom de ce site.
    @ObservationIgnored private var pages: [ObjectIdentifier: OpenPage] = [:]

    private struct OpenPage {
        weak var tab: BrowserTab?
        let site: String
    }

    /// `defaults` : où retenir les zooms ; nil pour une fenêtre privée ou une base de test (rien n'est écrit).
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        levels = Self.load(from: defaults)
    }

    /// Vrai si les zooms sont enregistrés (faux pour une fenêtre privée).
    var isPersistent: Bool {
        defaults != nil
    }

    /// Zoom retenu pour `site` ; 100 % sans site ou sans réglage.
    func level(forSite site: String?) -> Double {
        site.flatMap { levels[$0] } ?? ZoomLevels.actualSize
    }

    /// Nouveau document dans `tab` (`didCommit`, rechargement et retour en arrière compris) : la page prend le zoom
    /// de son site, ou 100 % sans site, et suivra désormais les changements du zoom de ce site.
    func pageDidCommit(_ tab: BrowserTab, url: URL?) {
        let site = SiteZoomKey.key(for: url)
        track(tab, site: site)
        tab.setPageZoom(level(forSite: site))
    }

    /// ⌘+, ⌘-, ⌘0 sur `tab` : le site de son document retient `level`, et chacune de ses pages ouvertes le prend.
    /// Une page sans site change seule, et rien n'est retenu.
    func setZoom(_ level: Double, for tab: BrowserTab) {
        guard let site = site(of: tab) ?? SiteZoomKey.key(for: tab.url) else {
            tab.setPageZoom(ZoomLevels.clamped(level))
            return
        }
        track(tab, site: site)
        setLevel(level, forSite: site)
    }

    /// Réglages du site : `site` retient `level` (100 % l'oublie), et toutes ses pages ouvertes le prennent.
    func setLevel(_ level: Double, forSite site: String) {
        let level = ZoomLevels.clamped(level)
        levels[site] = ZoomLevels.isActualSize(level) ? nil : level
        save()
        for page in pages.values where page.site == site {
            page.tab?.setPageZoom(level)
        }
        Logger.browser.info("Zoom d'un site : \(Int((level * 100).rounded()), privacy: .public) %, \(site, privacy: .private)")
    }

    /// Site du document affiché par `tab`, s'il est suivi.
    private func site(of tab: BrowserTab) -> String? {
        guard let page = pages[ObjectIdentifier(tab)], page.tab === tab else {
            return nil
        }
        return page.site
    }

    /// Suit `tab` sous `site` (nil : ne la suit plus) ; les pages libérées sont oubliées au passage.
    private func track(_ tab: BrowserTab, site: String?) {
        pages = pages.filter { $0.value.tab != nil }
        pages[ObjectIdentifier(tab)] = site.map { OpenPage(tab: tab, site: $0) }
    }

    private func save() {
        guard let defaults else {
            return
        }
        if levels.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(levels, forKey: Self.defaultsKey)
        }
    }

    /// Zooms enregistrés, ramenés entre 50 % et 300 % ; une valeur illisible ou à 100 % est ignorée.
    private static func load(from defaults: UserDefaults?) -> [String: Double] {
        let stored = defaults?.dictionary(forKey: defaultsKey) ?? [:]
        var levels: [String: Double] = [:]
        for (site, value) in stored {
            guard !site.isEmpty, let level = (value as? NSNumber)?.doubleValue, level.isFinite else {
                Logger.browser.notice("Zoom enregistré illisible, ignoré")
                continue
            }
            let clamped = ZoomLevels.clamped(level)
            if !ZoomLevels.isActualSize(clamped) {
                levels[site] = clamped
            }
        }
        return levels
    }
}
