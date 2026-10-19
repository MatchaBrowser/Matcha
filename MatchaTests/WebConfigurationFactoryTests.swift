@testable import Matcha
import Testing
import WebKit

@MainActor
struct WebConfigurationFactoryTests {
    @Test func `uses given website data store`() {
        let store = WKWebsiteDataStore.nonPersistent()
        let configuration = WebConfigurationFactory().makeConfiguration(websiteDataStore: store)
        #expect(configuration.websiteDataStore === store)
    }

    @Test func `enables element fullscreen`() {
        let configuration = WebConfigurationFactory().makeConfiguration(websiteDataStore: .nonPersistent())
        #expect(configuration.preferences.isElementFullscreenEnabled)
    }

    /// Task 5.10: the sound script, at the start of each document, iframes included.
    @Test func `installs the audio script in every frame`() throws {
        let configuration = WebConfigurationFactory().makeConfiguration(websiteDataStore: .nonPersistent())
        let scripts = configuration.userContentController.userScripts.filter { $0.source == PageAudioScript.source }
        let script = try #require(scripts.first)
        #expect(scripts.count == 1)
        #expect(script.injectionTime == .atDocumentStart)
        #expect(!script.isForMainFrameOnly)
    }

    /// Task 6.2: each page has its own content controller, which the blocker configures without touching the others.
    @Test func `a new page keeps a configuration whose controller is free`() {
        let configuration = WebConfigurationFactory().makeConfiguration(websiteDataStore: .nonPersistent())
        let controller = configuration.userContentController
        let tab = BrowserTab(configuration: configuration)
        #expect(tab.configuration === configuration)
        #expect(tab.loadedWebView.configuration.userContentController === controller)
    }

    /// Duplicated page, Peek, ⌘-clicked link: a copy of the configuration (same profile, same scheme handler), with a
    /// fresh controller that also has the sound script; the originating page keeps its own.
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

    /// Window requested by WebKit: the provided configuration itself gets a fresh controller.
    @Test func `a window requested by webkit gets its own controller in place`() {
        let configuration = WebConfigurationFactory().makeConfiguration(websiteDataStore: .nonPersistent())
        let shared = configuration.userContentController
        WebConfigurationFactory.giveOwnContentController(to: configuration)
        #expect(configuration.userContentController !== shared)
        #expect(configuration.userContentController.userScripts.contains { $0.source == PageAudioScript.source })
        #expect(BrowserTab(configuration: configuration).configuration === configuration)
    }
}
