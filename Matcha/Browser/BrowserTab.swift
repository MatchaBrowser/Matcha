import AppKit
import Observation
import OSLog
import WebKit

/// Un onglet en cours d'exécution : il possède sa vue web et expose son état à l'interface.
/// L'état est recopié depuis la vue web par observation KVO. La vue web peut être libérée
/// (`unload`, ou `suspend` pour la mémoire) puis recréée à la demande (`makeWebViewIfNeeded`).
@MainActor
@Observable
final class BrowserTab: Identifiable {
    let id: UUID
    /// Onglet depuis lequel celui-ci a été ouvert (lien, `window.open`), s'il y en a un.
    let openerID: BrowserTab.ID?

    /// Vue web de l'onglet ; nil quand il est déchargé.
    private(set) var webView: WKWebView?
    private(set) var title: String?
    private(set) var url: URL?
    /// `url != nil`, suivi à part : une vue qui n'a besoin que de savoir si l'onglet a une adresse
    /// (menu « Copier l'URL ») n'est pas recalculée à chaque changement d'adresse.
    private(set) var hasURL = false
    private(set) var isLoading = false
    private(set) var progress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// Icône du site, fournie par `FaviconService` ; nil tant qu'elle n'est pas connue.
    var favicon: Favicon?
    /// Adresse et titre d'origine d'un onglet épinglé ou favori : il y revient quand on le ferme.
    var pinnedURL: URL?
    var pinnedTitle: String?
    /// Dernière fois que l'onglet a été sélectionné (restauration de la sélection, classement de la
    /// barre de commande).
    var lastActivity = Date.now
    /// État de navigation retenu pour la restauration (historique précédent/suivant, défilement).
    var savedInteractionState: Data?
    /// Demandes de permission de la page qui attendent une réponse (bandeau, tâche 5.2).
    let permissionPrompts = PermissionPromptQueue()
    /// Recherche dans la page (barre, texte, résultat ; tâche 5.3).
    let find = FindSession()
    /// Visites de la page retenues dans l'historique (tâche 5.5).
    let history = PageHistory()
    /// Mise en veille pour la mémoire (tâche 5.6).
    let suspension = TabSuspension()
    /// Reprise après un arrêt du processus de la page (tâche 5.7).
    let crash = PageCrashRecovery()
    /// Son joué par la page : icône haut-parleur de la barre latérale (tâche 5.10).
    let audio = PageAudio()
    /// Zoom de la page (`WKWebView.pageZoom`, tâche 5.4), recopié ici pour les menus : il ne change que par
    /// `setPageZoom`. Le zoom par pincement (`magnification`) est à part.
    private(set) var pageZoom = ZoomLevels.actualSize

    /// Délégué de navigation et d'interface, branché sur chaque vue web créée (et sur la vue actuelle).
    @ObservationIgnored weak var delegate: (any WKNavigationDelegate & WKUIDelegate)? {
        didSet {
            webView?.navigationDelegate = delegate
            webView?.uiDelegate = delegate
        }
    }

    /// Configuration des vues web de l'onglet (même profil, mêmes réglages à chaque recréation).
    @ObservationIgnored private(set) var configuration: WKWebViewConfiguration
    /// Adresse à charger à la prochaine création de la vue web.
    @ObservationIgnored private var pendingURL: URL?
    /// État à rétablir à la prochaine création de la vue web, plutôt que de recharger l'adresse.
    @ObservationIgnored private var pendingInteractionState: Data?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    /// La première vue web est créée avec exactement cette configuration (obligatoire pour `window.open`), sauf si son
    /// contrôleur de contenu sert déjà à une autre page : copie avec un contrôleur neuf (bloqueur, tâche 6.2).
    init(id: UUID = UUID(), configuration: WKWebViewConfiguration, openerID: BrowserTab.ID? = nil) {
        self.id = id
        self.configuration = WebConfigurationFactory.pageConfiguration(from: configuration)
        self.openerID = openerID
        find.performer = self
        history.page = self
        suspension.page = self
        crash.page = self
    }

    /// Onglet restauré depuis l'enregistrement : il affiche `url` et `title`, et ne crée sa vue web
    /// (qui chargera `url`) qu'au premier affichage.
    convenience init(restoring stored: StoredTab, configuration: WKWebViewConfiguration) {
        self.init(id: stored.id, configuration: configuration)
        setURL(stored.url)
        title = stored.title
        pendingURL = stored.url
        pinnedURL = stored.pinnedURL
        pinnedTitle = stored.pinnedTitle
        lastActivity = stored.lastActivity
        savedInteractionState = stored.interactionState
        pendingInteractionState = stored.interactionState
    }

    var isLoaded: Bool {
        webView != nil
    }

    /// Affiché comme chargé dans la barre latérale (titre plein, bouton de fermeture) : vue web présente, ou mise en
    /// veille pour la mémoire, qui ne doit rien changer à l'affichage (tâche 5.6).
    var appearsLoaded: Bool {
        webView != nil || suspension.isSuspended
    }

    /// Vue web de l'onglet, créée si besoin ; un onglet déchargé recharge alors son adresse, un onglet en veille sa
    /// page et son historique, sans compter une nouvelle visite.
    @discardableResult
    func makeWebViewIfNeeded() -> WKWebView {
        if let webView {
            return webView
        }
        let webView = BrowserWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        #if DEBUG
            webView.isInspectable = true
        #endif
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.pageZoom = pageZoom
        webView.audio = audio
        // Copie réutilisable pour les prochaines vues (rechargement, duplication).
        configuration = webView.configuration
        self.webView = webView
        if suspension.isSuspended {
            // Avant l'observation : le titre vide et l'adresse absente de la vue neuve ne remplacent pas ceux de l'onglet.
            suspension.didResume(url: url)
            history.pageWillResume(url: url)
        }
        observe(webView)
        if let state = pendingInteractionState {
            // Restauration : page, historique et défilement, sans recharger depuis l'adresse.
            pendingInteractionState = nil
            pendingURL = nil
            webView.interactionState = state
        } else if let pendingURL {
            self.pendingURL = nil
            load(pendingURL, in: webView)
        }
        return webView
    }

    /// Retient l'état de navigation de la vue web, pour la restaurer plus tard ; faux s'il n'a pas pu être lu.
    @discardableResult
    func captureInteractionState() -> Bool {
        guard let webView else {
            return false
        }
        guard let state = webView.interactionState as? Data else {
            Logger.browser.notice("État de navigation illisible : l'onglet sera restauré depuis son adresse")
            return false
        }
        savedInteractionState = state
        return true
    }

    /// Libère la vue web (mémoire, son, processus), refuse les demandes de permission en attente, oublie la recherche
    /// dans la page et revient à 100 % (le zoom du site reviendra avec la page). L'onglet affiche désormais `url` et
    /// `title`, et chargera `url` quand on le rouvrira.
    func unload(resettingTo url: URL?, title: String?) {
        releaseWebView()
        history.reset()
        suspension.reset()
        pendingURL = url
        // Retour à l'adresse d'origine : l'historique est oublié.
        pendingInteractionState = nil
        savedInteractionState = nil
        setURL(url)
        self.title = title
        canGoBack = false
        canGoForward = false
        pageZoom = ZoomLevels.actualSize
    }

    /// Met l'onglet en veille pour la mémoire (tâche 5.6) : son état de navigation est retenu et sa vue web libérée,
    /// comme `unload`, mais il garde son adresse, son titre, son icône, son zoom et son historique précédent/suivant.
    /// Recréé, il rouvre la même page (depuis son adresse si l'état n'a pas pu être lu). `snapshot` : sa capture.
    func suspend(snapshot: TabSnapshot?, at date: Date = .now) {
        guard webView != nil else {
            return
        }
        if !captureInteractionState() {
            // Un état plus ancien que la page affichée (retenu au dernier chargement) ne doit pas la remplacer.
            savedInteractionState = nil
        }
        releaseWebView()
        history.reset()
        pendingURL = url
        pendingInteractionState = savedInteractionState
        suspension.didSuspend(snapshot: snapshot, at: date)
    }

    /// Relit le titre et l'adresse de la vue web (fin du rechargement d'un onglet sorti de veille). Une vue sans
    /// adresse (rechargement échoué) ne vide pas l'onglet.
    func syncWithWebView() {
        guard let webView, webView.url != nil else {
            return
        }
        title = webView.title
        setURL(webView.url)
    }

    func load(_ url: URL) {
        let webView = makeWebViewIfNeeded()
        // Une autre page que celle de la veille : plus de capture par-dessus ; une page plantée quitte son message.
        suspension.endRestoring()
        crash.pageWillNavigate()
        load(url, in: webView)
    }

    /// Zoom de la page (100 % = 1) ; gardé pour la vue web recréée après un déchargement.
    func setPageZoom(_ zoom: Double) {
        if pageZoom != zoom {
            pageZoom = zoom
        }
        webView?.pageZoom = zoom
    }

    /// Libère la vue web : observation, son (icône comprise), chargement, délégués ; refuse les demandes de permission
    /// en attente, oublie la recherche dans la page et la reprise d'un arrêt du processus (message compris).
    private func releaseWebView() {
        observations = []
        permissionPrompts.denyAll()
        find.reset()
        audio.reset()
        if let webView {
            (webView as? BrowserWebView)?.audio = nil
            webView.pauseAllMediaPlayback(completionHandler: nil)
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
        webView = nil
        isLoading = false
        progress = 0
        crash.end()
    }

    private func load(_ url: URL, in webView: WKWebView) {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    /// `hasURL` n'est modifié (et ne prévient ses observateurs) que si l'onglet gagne ou perd son adresse. Une
    /// autre adresse rend caduc le dernier résultat de la recherche dans la page.
    private func setURL(_ newURL: URL?) {
        if newURL != url {
            find.pageDidChange()
        }
        url = newURL
        let hasNewURL = newURL != nil
        if hasURL != hasNewURL {
            hasURL = hasNewURL
        }
    }

    private func observe(_ webView: WKWebView) {
        observations = [
            webView.observe(\.title, options: .initial, changeHandler: sync { tab, webView in
                // Sortie de veille, arrêt du processus : l'onglet garde son titre jusqu'à celui de la page rechargée.
                if tab.keepsTitleAndAddress, webView.title?.isEmpty != false {
                    return
                }
                tab.title = webView.title
                tab.history.titleDidChange(to: webView.title, pageURL: webView.url)
            }),
            webView.observe(\.url, options: .initial, changeHandler: sync { tab, webView in
                if tab.keepsTitleAndAddress, webView.url == nil {
                    return
                }
                tab.suspension.pageURLDidChange(to: webView.url)
                tab.setURL(webView.url)
                // Chargement lu sur la vue web : WebKit change l'adresse et le chargement ensemble, avant que l'onglet
                // n'ait recopié le second.
                tab.history.urlDidChange(to: webView.url, isLoading: webView.isLoading)
            }),
            webView.observe(\.isLoading, options: .initial, changeHandler: sync { $0.isLoading = $1.isLoading }),
            webView.observe(\.estimatedProgress, options: .initial, changeHandler: sync { $0.progress = $1.estimatedProgress }),
            webView.observe(\.canGoBack, options: .initial, changeHandler: sync { $0.canGoBack = $1.canGoBack }),
            webView.observe(\.canGoForward, options: .initial, changeHandler: sync { $0.canGoForward = $1.canGoForward }),
        ]
    }

    /// Fabrique un gestionnaire KVO qui recopie l'état de la vue web dans l'onglet.
    /// WebKit émet ses notifications KVO sur le fil principal. Une vue déjà remplacée est ignorée.
    private func sync<Value>(
        _ apply: @escaping @MainActor @Sendable (BrowserTab, WKWebView) -> Void,
    ) -> @Sendable (WKWebView, NSKeyValueObservedChange<Value>) -> Void {
        { [weak self] webView, _ in
            MainActor.assumeIsolated {
                guard let self, self.webView === webView else {
                    return
                }
                apply(self, webView)
            }
        }
    }
}
