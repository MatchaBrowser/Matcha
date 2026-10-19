import Foundation
import WebKit

/// Web developer tools (“Show features for web developers” setting, Settings > Advanced): “Inspect Element” in the
/// page menu opens the web inspector in Matcha, and pages and extensions can also be inspected from Safari's Develop
/// menu. Off by default (on in Debug), followed at once by the open pages (`didChange`).
///
/// Exception to the public API rule, wanted by the user (`DECISIONS.md`, 2026-10-18): WebKit only offers the in-app
/// inspector through its private `developerExtrasEnabled` preference. It is only set if `WKPreferences` still knows
/// it; otherwise, nothing breaks and only inspection from Safari (`isInspectable`, public) remains.
@MainActor
enum WebInspection {
    /// The setting changed: the web views pick it up.
    static let didChange = Notification.Name("MatchaWebInspectionDidChange")

    /// Private WebKit setter behind the `developerExtrasEnabled` key.
    private static let developerExtrasSetter = NSSelectorFromString("_setDeveloperExtrasEnabled:")

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: BrowserSettings.Key.showsDeveloperTools) == nil
            ? BrowserSettings.showsDeveloperTools
            : defaults.bool(forKey: BrowserSettings.Key.showsDeveloperTools)
    }

    /// True if this WebKit allows the in-app inspector.
    static var offersInAppInspector: Bool {
        WKPreferences().responds(to: developerExtrasSetter)
    }

    static func apply(to webView: WKWebView, enabled: Bool = isEnabled()) {
        webView.isInspectable = enabled
        apply(to: webView.configuration.preferences, enabled: enabled)
    }

    static func apply(to preferences: WKPreferences, enabled: Bool = isEnabled()) {
        guard preferences.responds(to: developerExtrasSetter) else {
            return
        }
        preferences.setValue(enabled, forKey: "developerExtrasEnabled")
    }
}
