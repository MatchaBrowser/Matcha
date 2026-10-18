@testable import Matcha
import Testing
import WebKit

@MainActor
struct WebConfigurationFactoryTests {
    @Test func `uses given website data store`() {
        let store = WKWebsiteDataStore.nonPersistent()
        let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: store)
        #expect(configuration.websiteDataStore === store)
    }

    @Test func `enables element fullscreen`() {
        let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent())
        #expect(configuration.preferences.isElementFullscreenEnabled)
    }

    @Test func `announces safari in user agent`() {
        let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent())
        #expect(configuration.applicationNameForUserAgent == "Version/26.6 Safari/605.1.15")
    }

    /// Tâche 5.10 : le script de son, au début de chaque document, iframes comprises.
    @Test func `installs the audio script in every frame`() throws {
        let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent())
        let scripts = configuration.userContentController.userScripts.filter { $0.source == PageAudioScript.source }
        let script = try #require(scripts.first)
        #expect(scripts.count == 1)
        #expect(script.injectionTime == .atDocumentStart)
        #expect(!script.isForMainFrameOnly)
    }

    /// Tâche 6.2 : chaque page a son propre contrôleur de contenu, que le bloqueur règle sans toucher aux autres.
    @Test func `a new page keeps a configuration whose controller is free`() {
        let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent())
        let controller = configuration.userContentController
        let tab = BrowserTab(configuration: configuration)
        #expect(tab.configuration === configuration)
        #expect(tab.loadedWebView.configuration.userContentController === controller)
    }

    /// Page dupliquée, aperçu, lien ⌘-clic : une copie de la configuration (même profil, même gestionnaire de schéma),
    /// avec un contrôleur neuf qui a lui aussi le script de son ; la page d'origine garde le sien.
    @Test func `a page reusing another page's configuration gets its own controller`() {
        let configuration = TestPages.configuration()
        let source = BrowserTab(configuration: configuration)
        let sourceController = source.loadedWebView.configuration.userContentController
        let copy = BrowserTab(configuration: source.configuration)
        let copyConfiguration = copy.loadedWebView.configuration
        #expect(copyConfiguration.userContentController !== sourceController)
        #expect(copyConfiguration.websiteDataStore === configuration.websiteDataStore)
        #expect(copyConfiguration.urlSchemeHandler(forURLScheme: TestPages.scheme) != nil)
        #expect(copyConfiguration.userContentController.userScripts.contains { $0.source == PageAudioScript.source })
        #expect(source.loadedWebView.configuration.userContentController === sourceController)
        #expect(source.configuration.userContentController === sourceController)
    }

    /// Fenêtre demandée par WebKit : la configuration fournie reçoit un contrôleur neuf, sur elle-même.
    @Test func `a window requested by webkit gets its own controller in place`() {
        let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent())
        let shared = configuration.userContentController
        WebConfigurationFactory.giveOwnContentController(to: configuration)
        #expect(configuration.userContentController !== shared)
        #expect(configuration.userContentController.userScripts.contains { $0.source == PageAudioScript.source })
        #expect(BrowserTab(configuration: configuration).configuration === configuration)
    }
}
