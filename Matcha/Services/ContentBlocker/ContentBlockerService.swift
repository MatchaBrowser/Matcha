import Foundation
import Observation
import OSLog
import WebKit

/// Bloqueur de publicités et de traqueurs (tâche 6.2), un pour toute l'app : tous les profils, les mini-fenêtres et les
/// fenêtres privées. Au lancement, les listes livrées (`BlocklistBundle`) sont relues ou compilées dans le magasin de
/// WebKit (`BlocklistLoader`) sans bloquer l'interface : les pages se chargent sans bloqueur jusque-là, puis les listes
/// sont posées sur chaque page suivie et sur les suivantes. Chaque page a son propre contrôleur de contenu ; avant chaque
/// navigation de son document principal, ses listes y sont posées, ou retirées si son site est en exception
/// (`ContentBlockerScope`). Une règle `ignore-previous-rules` ne passe pas d'une liste à l'autre dans WebKit : une
/// liste d'exceptions à part n'aurait aucun effet (`DECISIONS.md`). Réglage global « Bloquer les publicités et les
/// traqueurs » (actif par défaut) ; le changer vaut pour les prochains chargements, sans recharger les pages.
@MainActor
@Observable
final class ContentBlockerService {
    static let shared = ContentBlockerService(defaults: .standard)

    enum State: Equatable {
        /// Pas lancé (app hôte des tests unitaires, tests).
        case idle
        case loading
        case ready
    }

    /// Une liste prête, pour les réglages.
    struct InstalledList: Identifiable, Equatable {
        let entry: BlocklistEntry
        let record: CompiledBlocklist

        var id: String {
            entry.identifier
        }
    }

    private(set) var state = State.idle
    /// Listes prêtes, dans l'ordre du manifeste.
    private(set) var installedLists: [InstalledList] = []
    /// Réglage « Bloquer les publicités et les traqueurs ».
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else {
                return
            }
            defaults?.set(isEnabled, forKey: BrowserSettings.Key.blocksAdsAndTrackers)
            let state = isEnabled ? "activé" : "désactivé"
            Logger.contentBlocker.info("Bloqueur \(state, privacy: .public)")
            applyToPages(reloadingSite: nil)
        }
    }

    /// Sites où le bloqueur est désactivé, enregistrés.
    @ObservationIgnored let exceptions: ContentBlockerExceptions
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var ruleLists: [WKContentRuleList] = []
    @ObservationIgnored private var pages = ContentBlockerPages()
    /// Site d'une adresse pour les exceptions (remplacé dans les tests : leurs pages `obtest:` n'ont pas de site web).
    @ObservationIgnored var siteOfURL: (URL?) -> String? = ContentBlockerExceptions.site(for:)

    /// `defaults` : réglages et listes compilées retenues ; nil (tests) : rien n'est lu ni écrit.
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        exceptions = ContentBlockerExceptions(defaults: defaults)
        isEnabled = BrowserSettings.blocksAdsAndTrackers(in: defaults)
    }

    /// Vrai quand au moins une liste est prête.
    var hasLists: Bool {
        !installedLists.isEmpty
    }

    /// Pages suivies encore ouvertes (tests).
    var trackedPageCount: Int {
        pages.count
    }

    /// Au lancement de l'app : prépare les listes livrées, en tâche de fond. Sans effet s'il est déjà lancé.
    func start() {
        guard state == .idle else {
            return
        }
        state = .loading
        Task {
            await load(from: BlocklistBundle(bundle: .main), store: .default())
        }
    }

    /// Prépare les listes de `source` dans `store`, puis les pose sur les pages suivies. Les tests donnent leurs listes et
    /// un magasin temporaire, jamais celui de l'app.
    func load(from source: BlocklistBundle, store: WKContentRuleListStore) async {
        state = .loading
        let clock = ContinuousClock()
        let start = clock.now
        let entries = await manifestEntries(from: source)
        let loader = BlocklistLoader(store: store, readRules: { try await source.rules(of: $0) })
        let loaded = await loader.load(entries, previous: CompiledBlocklist.load(from: defaults))
        CompiledBlocklist.save(loaded.map(\.record), to: defaults)
        // Listes d'un chargement précédent retirées des pages avant de poser les nouvelles.
        pages.apply(ruleLists) { _ in false }
        ruleLists = loaded.flatMap(\.ruleLists)
        installedLists = loaded.map { InstalledList(entry: $0.entry, record: $0.record) }
        state = .ready
        let compiled = loaded.count { $0.wasCompiled }
        let duration = (clock.now - start).formatted(.units(allowed: [.seconds, .milliseconds]))
        Logger.contentBlocker.info(
            "Listes prêtes : \(loaded.count, privacy: .public) (\(compiled, privacy: .public) compilées), en \(duration, privacy: .public)",
        )
        applyToPages(reloadingSite: nil)
    }

    /// Le document principal de `webView` va être `url` (navigation autorisée, ou document affiché) : les listes y
    /// sont posées, ou retirées si son site est en exception pour `scope`.
    func prepare(_ webView: WKWebView, for url: URL?, scope: ContentBlockerScope?) {
        let key = pages.track(webView, site: siteOfURL(url), scope: scope)
        pages.apply(ruleLists, only: key, blocks: blocks)
    }

    /// Désactive (`isExcepted`) ou réactive le bloqueur sur `site`, enregistré ; ses pages ouvertes se rechargent.
    func setException(_ isExcepted: Bool, forSite site: String) {
        guard let site = ContentBlockerExceptions.normalized(site), exceptions.set(isExcepted, forSite: site) else {
            return
        }
        Logger.contentBlocker.info("Bloqueur \(isExcepted ? "désactivé" : "réactivé", privacy: .public) sur un site")
        exceptionsDidChange(forSite: site)
    }

    /// L'exception de `site` a changé (enregistrée, ou dans une fenêtre privée) : les pages de ce site dont l'état
    /// change se rechargent.
    func exceptionsDidChange(forSite site: String) {
        applyToPages(reloadingSite: site)
    }

    /// Pose ou retire les listes sur toutes les pages ; recharge celles de `site` qui ont changé.
    private func applyToPages(reloadingSite site: String?) {
        let changed = pages.apply(ruleLists, blocks: blocks)
        guard let site else {
            return
        }
        for page in changed where page.site == site {
            page.webView?.reload()
        }
    }

    /// Vrai si les listes doivent être sur `page` : bloqueur actif, listes prêtes, site sans exception.
    private func blocks(_ page: ContentBlockerPages.Page) -> Bool {
        guard isEnabled, !ruleLists.isEmpty else {
            return false
        }
        guard let site = page.site, let scope = page.scope else {
            return true
        }
        return !scope.isExcepted(site: site)
    }

    private func manifestEntries(from source: BlocklistBundle) async -> [BlocklistEntry] {
        do {
            let lists = try await source.manifest()?.lists ?? []
            if lists.isEmpty {
                Logger.contentBlocker.info("Aucune liste de blocage livrée : bloqueur inactif")
            }
            return lists
        } catch {
            let reason = error.localizedDescription
            Logger.contentBlocker.error("Manifeste des listes de blocage illisible, bloqueur inactif : \(reason, privacy: .public)")
            return []
        }
    }
}
