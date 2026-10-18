import WebKit

/// Fabrique la configuration WebKit commune à toutes les vues web, avec le script de son (tâche 5.10) et le contrôleur
/// des extensions (tâche 6.3, fenêtres privées comprises : les extensions n'y ont accès que si l'utilisateur le permet).
/// Chaque page a son propre contrôleur de contenu (`pageConfiguration`) : le bloqueur (tâche 6.2) y pose ou retire ses
/// listes page par page ; WebKit y injecte les scripts des extensions.
@MainActor
enum WebConfigurationFactory {
    /// Version de Safari annoncée aux sites, pour qu'ils traitent l'app comme Safari.
    /// À tenir à jour avec la version de Safari livrée avec macOS.
    static let safariVersion = "26.6"

    /// Contrôleurs de contenu déjà donnés à une page (`BrowserTab`).
    private static let pageControllers = NSHashTable<WKUserContentController>.weakObjects()

    /// Suffixe ajouté par WebKit à son agent utilisateur.
    static var applicationNameForUserAgent: String {
        "Version/\(safariVersion) Safari/605.1.15"
    }

    static func makeConfiguration(websiteDataStore: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.preferences.isElementFullscreenEnabled = true
        WebInspection.apply(to: configuration.preferences)
        configuration.applicationNameForUserAgent = applicationNameForUserAgent
        configuration.userContentController = makeUserContentController()
        // « Afficher le code source » (menu d'une page).
        configuration.setURLSchemeHandler(PageSourceSchemeHandler.shared, forURLScheme: PageSource.scheme)
        ExtensionManager.shared.attach(to: configuration)
        return configuration
    }

    /// Contrôleur de contenu d'une page, avec le script de son.
    static func makeUserContentController() -> WKUserContentController {
        let controller = WKUserContentController()
        PageAudioScript.install(in: controller)
        return controller
    }

    /// Configuration d'une nouvelle page (`BrowserTab`) : `configuration` telle quelle si son contrôleur de contenu
    /// n'appartient encore à aucune page ; sinon (page dupliquée, aperçu, lien ⌘-clic, qui reprennent la configuration
    /// d'une autre page), une copie (même profil, mêmes réglages) avec un contrôleur neuf. Le bloqueur peut ainsi régler
    /// chaque page sans toucher aux autres.
    static func pageConfiguration(from configuration: WKWebViewConfiguration) -> WKWebViewConfiguration {
        var configuration = configuration
        if pageControllers.contains(configuration.userContentController), let copy = configuration.copy() as? WKWebViewConfiguration {
            copy.userContentController = makeUserContentController()
            configuration = copy
        }
        pageControllers.add(configuration.userContentController)
        return configuration
    }

    /// Fenêtre ouverte par une page (`createWebViewWith`) : la configuration fournie par WebKit partage le contrôleur de
    /// la page d'origine ; elle en reçoit un neuf, sur elle-même (WebKit exige que la vue soit créée avec cet objet ;
    /// `window.opener` reste, vérifié).
    static func giveOwnContentController(to configuration: WKWebViewConfiguration) {
        configuration.userContentController = makeUserContentController()
    }
}
