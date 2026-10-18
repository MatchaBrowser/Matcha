import AppKit
import WebKit

/// Page qui a ouvert une fenêtre de connexion (tâche 5.8), relevée à l'ouverture : son hôte et sa vue web (où vont les
/// liens ⌘-clic et les fenêtres sans taille de la fenêtre de connexion), sa page (jamais mise en veille tant que la
/// fenêtre est ouverte, sans quoi `window.opener` la perdrait : tâche 5.6), sa fenêtre (au-dessus de laquelle la
/// fenêtre de connexion reste), et ce qui suit son profil : décisions de permission et historique. Les références
/// sont faibles : la page d'origine peut se fermer avant la fenêtre de connexion, qui reste alors ouverte.
@MainActor
struct PopupOpener {
    private(set) weak var host: (any TabHost)?
    private(set) weak var webView: WKWebView?
    private(set) weak var page: BrowserTab?
    private(set) weak var window: NSWindow?
    let sitePermissions: SitePermissionScope?
    let history: HistoryScope?

    init(host: any TabHost, webView: WKWebView) {
        self.host = host
        self.webView = webView
        page = host.page(for: webView)
        window = webView.window
        sitePermissions = host.sitePermissions(for: webView)
        history = host.historyScope(for: webView)
    }

    /// Hôte et vue web de la page d'origine, s'il l'affiche encore (onglet ouvert, aperçu ou mini-fenêtre pas fermés).
    var liveSource: (host: any TabHost, webView: WKWebView)? {
        guard let host, let webView, host.page(for: webView) != nil else {
            return nil
        }
        return (host, webView)
    }
}
