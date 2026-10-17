import AppKit
import Observation
import OSLog
import WebKit

/// Un onglet en cours d'exécution : il possède sa vue web et expose son état à l'interface.
/// L'état est recopié depuis la vue web par observation KVO. La vue web peut être libérée
/// (`unload`) puis recréée à la demande (`makeWebViewIfNeeded`).
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

    /// La première vue web est créée avec exactement cette configuration : c'est obligatoire
    /// pour les vues demandées par WebKit (`window.open`, liens `target=_blank`).
    init(id: UUID = UUID(), configuration: WKWebViewConfiguration, openerID: BrowserTab.ID? = nil) {
        self.id = id
        self.configuration = configuration
        self.openerID = openerID
        find.performer = self
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

    /// Titre à afficher : titre de la page, sinon hôte, sinon « Nouvel onglet ».
    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        if let host = url?.host(), !host.isEmpty {
            return host
        }
        return url?.absoluteString ?? String(localized: "New Tab")
    }

    /// Vue web de l'onglet, créée si besoin ; un onglet déchargé recharge alors son adresse.
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
        // Copie réutilisable pour les prochaines vues (rechargement, duplication).
        configuration = webView.configuration
        self.webView = webView
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

    /// Retient l'état de navigation de la vue web, pour la restaurer plus tard.
    func captureInteractionState() {
        guard let webView else {
            return
        }
        guard let state = webView.interactionState as? Data else {
            Logger.browser.notice("État de navigation illisible : l'onglet sera restauré depuis son adresse")
            return
        }
        savedInteractionState = state
    }

    /// Libère la vue web (mémoire, son, processus), refuse les demandes de permission en attente, oublie la recherche
    /// dans la page et revient à 100 % (le zoom du site reviendra avec la page). L'onglet affiche désormais `url` et
    /// `title`, et chargera `url` quand on le rouvrira.
    func unload(resettingTo url: URL?, title: String?) {
        observations = []
        permissionPrompts.denyAll()
        find.reset()
        if let webView {
            webView.pauseAllMediaPlayback(completionHandler: nil)
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
        webView = nil
        pendingURL = url
        // Retour à l'adresse d'origine : l'historique est oublié.
        pendingInteractionState = nil
        savedInteractionState = nil
        setURL(url)
        self.title = title
        isLoading = false
        progress = 0
        canGoBack = false
        canGoForward = false
        pageZoom = ZoomLevels.actualSize
    }

    func load(_ url: URL) {
        load(url, in: makeWebViewIfNeeded())
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func stop() {
        webView?.stopLoading()
    }

    /// Zoom de la page (100 % = 1) ; gardé pour la vue web recréée après un déchargement.
    func setPageZoom(_ zoom: Double) {
        if pageZoom != zoom {
            pageZoom = zoom
        }
        webView?.pageZoom = zoom
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
            webView.observe(\.title, options: .initial, changeHandler: sync { $0.title = $1.title }),
            webView.observe(\.url, options: .initial, changeHandler: sync { $0.setURL($1.url) }),
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
