import Foundation
@testable import Matcha
import Testing
import WebKit

/// Outils pour développeurs web : pages inspectables, inspecteur dans l'app si WebKit le permet.
@MainActor
struct WebInspectionTests {
    @Test func `the setting makes pages inspectable, with the in-app inspector`() {
        let webView = BrowserWebView(frame: .zero, configuration: WKWebViewConfiguration())
        WebInspection.apply(to: webView, enabled: true)
        #expect(webView.isInspectable)
        if WebInspection.offersInAppInspector {
            #expect(webView.configuration.preferences.value(forKey: "developerExtrasEnabled") as? Bool == true)
        }
        WebInspection.apply(to: webView, enabled: false)
        #expect(!webView.isInspectable)
        if WebInspection.offersInAppInspector {
            #expect(webView.configuration.preferences.value(forKey: "developerExtrasEnabled") as? Bool == false)
        }
    }

    @Test func `off by default outside Debug builds`() throws {
        let defaults = try #require(UserDefaults(suiteName: "WebInspectionTests-\(UUID().uuidString)"))
        #expect(WebInspection.isEnabled(in: defaults) == BrowserSettings.showsDeveloperTools)
        defaults.set(false, forKey: BrowserSettings.Key.showsDeveloperTools)
        #expect(!WebInspection.isEnabled(in: defaults))
    }
}
