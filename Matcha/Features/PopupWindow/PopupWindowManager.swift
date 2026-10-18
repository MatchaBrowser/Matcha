import AppKit
import OSLog
import WebKit

/// Fenêtres de connexion d'une session (tâche 5.8) : une page qui ouvre une fenêtre en donnant sa taille
/// (`window.open(url, nom, "width=500,height=600")` : connexion Google ou Apple, banque, paiement) l'obtient dans sa
/// propre petite fenêtre, au-dessus de sa fenêtre d'origine, au lieu d'un onglet ; depuis un aperçu, l'aperçu reste un
/// aperçu ; depuis une mini-fenêtre, de même. Une instance par session (`BrowserSession.popupWindows`) : celles d'une
/// fenêtre privée sont privées et se ferment avec elle. Les pages des fenêtres de connexion ont leur propre délégué de
/// navigation (hôte : ce gestionnaire, `+TabHost`) ; jamais enregistrées ni restaurées.
@MainActor
final class PopupWindowManager {
    let faviconService: FaviconService
    /// Fenêtre à laquelle reviennent leurs téléchargements : celle de la session.
    let downloadScope: DownloadScope
    /// Zoom des pages par site de la session (tâche 5.4).
    let siteZooms: SiteZoomStore?
    /// Fenêtre privée : fenêtres de connexion sombres, comme elle.
    let isPrivate: Bool
    /// Bloqueur de la session (tâche 6.2), donné par la session ; nil (tests) : les pages ne sont pas suivies.
    var contentBlocking: ContentBlockerScope?
    /// Délégué de navigation des pages des fenêtres de connexion.
    let coordinator = NavigationCoordinator()
    /// Fenêtres ouvertes, de la plus ancienne à la plus récente.
    private(set) var windows: [PopupWindowController] = []

    /// Montre la fenêtre au-dessus de sa fenêtre d'origine (remplacé dans les tests : aucune fenêtre à l'écran).
    var present: @MainActor (PopupWindowController) -> Void = PopupWindowManager.presentOnScreen
    /// Zone utile de l'écran de la fenêtre d'origine, ou de celui du pointeur sans elle (remplacée dans les tests).
    var visibleScreenFrame: @MainActor (NSWindow?) -> CGRect? = PopupWindowManager.visibleFrame(around:)

    init(faviconService: FaviconService, downloadScope: DownloadScope, siteZooms: SiteZoomStore?, isPrivate: Bool) {
        self.faviconService = faviconService
        self.downloadScope = downloadScope
        self.siteZooms = siteZooms
        self.isPrivate = isPrivate
        coordinator.tabHost = self
    }

    func window(for webView: WKWebView) -> PopupWindowController? {
        windows.first { $0.tab.webView === webView }
    }

    func window(for page: BrowserTab) -> PopupWindowController? {
        windows.first { $0.tab === page }
    }

    /// Vrai si une fenêtre ouverte par `page` l'est encore : `page` ne doit pas être mise en veille (tâche 5.6), sans
    /// quoi `window.opener` ne la retrouverait plus.
    func hasOpenWindow(openedBy page: BrowserTab) -> Bool {
        windows.contains { $0.opener.page === page }
    }

    // MARK: Ouverture

    /// Ouvre une fenêtre de connexion et renvoie sa vue web, créée avec `configuration` telle quelle (sans quoi
    /// `window.opener` ne fonctionne pas) ; WebKit y charge ensuite la page demandée.
    func open(configuration: WKWebViewConfiguration, features: PopupWindowFeatures, opener: PopupOpener) -> WKWebView {
        let tab = BrowserTab(configuration: configuration, openerID: opener.page?.id)
        return show(tab, features: features, opener: opener).tab.makeWebViewIfNeeded()
    }

    /// Crée la fenêtre de `tab`, à la taille demandée, centrée sur la fenêtre d'origine, et la montre.
    @discardableResult
    func show(_ tab: BrowserTab, features: PopupWindowFeatures, opener: PopupOpener) -> PopupWindowController {
        tab.delegate = coordinator
        // Vue web créée avant la fenêtre, avec son délégué : le conteneur la montre dès l'ouverture.
        tab.makeWebViewIfNeeded()
        let controller = PopupWindowController(
            tab: tab,
            opener: opener,
            frame: frame(for: features, opener: opener.window),
            isPrivate: isPrivate,
            manager: self,
        )
        windows.append(controller)
        present(controller)
        return controller
    }

    // MARK: Fermeture

    func didClose(_ controller: PopupWindowController) {
        windows.removeAll { $0 === controller }
    }

    /// Fenêtre privée fermée : ses fenêtres de connexion aussi (sa session est oubliée).
    func closeAll() {
        for controller in windows {
            controller.close()
        }
    }

    /// Profil supprimé : les fenêtres qui utilisent ses données se ferment avant qu'elles ne soient effacées.
    func closeWindows(using dataStore: WKWebsiteDataStore) {
        for controller in windows where controller.tab.configuration.websiteDataStore === dataStore {
            controller.close()
        }
    }

    // MARK: Écran

    /// Page à la taille demandée, plus la barre d'adresse et la barre de titre, dans la zone utile de l'écran.
    private func frame(for features: PopupWindowFeatures, opener: NSWindow?) -> CGRect {
        let page = PopupWindowPlacement.pageSize(for: features)
        let content = CGRect(x: 0, y: 0, width: page.width, height: page.height + PopupAddressBar.height)
        let size = NSWindow.frameRect(forContentRect: content, styleMask: PopupWindow.style).size
        let visible = visibleScreenFrame(opener) ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return PopupWindowPlacement.frame(size: size, opener: opener?.frame, in: visible)
    }

    /// Au-dessus de la fenêtre d'origine si elle est à l'écran, au premier plan ; la page prend le clavier.
    static func presentOnScreen(_ controller: PopupWindowController) {
        if let parent = controller.opener.window, parent.isVisible, !parent.isMiniaturized {
            controller.attach(to: parent)
        }
        controller.window.makeKeyAndOrderFront(nil)
        TabActivation.focusPage(of: controller.tab)
    }

    static func visibleFrame(around window: NSWindow?) -> CGRect? {
        window?.screen?.visibleFrame ?? MiniWindowManager.screenUnderPointer()
    }
}
