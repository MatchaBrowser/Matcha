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
}
