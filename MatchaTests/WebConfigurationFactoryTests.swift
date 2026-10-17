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
}
