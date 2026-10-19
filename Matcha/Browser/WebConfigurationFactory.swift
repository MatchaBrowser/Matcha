import WebKit

/// Builds the WebKit configuration shared by all web views, with the sound script (task 5.10) and the extension
/// controller (task 6.3, private windows included: extensions only have access to them if the user allows it).
/// Each page has its own content controller (`pageConfiguration`): the blocker (task 6.2) sets or removes its lists
/// there page by page; WebKit injects the extensions' scripts into it.
@MainActor
enum WebConfigurationFactory {
    /// Safari version announced to sites, so that they treat the app as Safari.
    /// To keep up to date with the Safari version shipped with macOS.
    static let safariVersion = "26.6"

    /// Content controllers already given to a page (`BrowserTab`).
    private static let pageControllers = NSHashTable<WKUserContentController>.weakObjects()

    /// Suffix added by WebKit to its user agent.
    static var applicationNameForUserAgent: String {
        "Version/\(safariVersion) Safari/605.1.15"
    }

    static func makeConfiguration(websiteDataStore: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.preferences.isElementFullscreenEnabled = true
        // Pop-up blocker (as in Safari): a page only opens a window or a tab right after a click or a key press.
        // WebKit's default on macOS lets scripts open as many as they want.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // An http address is tried in https first, then in http if that fails (audit W5; WebKit keeps the address as
        // requested by default).
        configuration.defaultWebpagePreferences.preferredHTTPSNavigationPolicy = .automaticFallbackToHTTP
        WebInspection.apply(to: configuration.preferences)
        configuration.applicationNameForUserAgent = applicationNameForUserAgent
        configuration.userContentController = makeUserContentController()
        // “View Page Source” (menu of a page).
        configuration.setURLSchemeHandler(PageSourceSchemeHandler.shared, forURLScheme: PageSource.scheme)
        ExtensionManager.shared.attach(to: configuration)
        return configuration
    }

    /// Content controller of a page, with the sound script.
    static func makeUserContentController() -> WKUserContentController {
        let controller = WKUserContentController()
        PageAudioScript.install(in: controller)
        return controller
    }

    /// Configuration of a new page (`BrowserTab`): `configuration` as is if its content controller does not belong to
    /// any page yet; otherwise (duplicated page, Peek, ⌘-click link, which reuse the configuration of another page), a
    /// copy (same profile, same settings) with a new controller. The blocker can thus adjust each page without touching
    /// the others.
    static func pageConfiguration(from configuration: WKWebViewConfiguration) -> WKWebViewConfiguration {
        var configuration = configuration
        if pageControllers.contains(configuration.userContentController), let copy = configuration.copy() as? WKWebViewConfiguration {
            copy.userContentController = makeUserContentController()
            configuration = copy
        }
        pageControllers.add(configuration.userContentController)
        return configuration
    }

    /// Window opened by a page (`createWebViewWith`): the configuration supplied by WebKit shares the controller of the
    /// originating page; it gets a new one, on itself (WebKit requires the view to be created with this object;
    /// `window.opener` remains, checked).
    static func giveOwnContentController(to configuration: WKWebViewConfiguration) {
        configuration.userContentController = makeUserContentController()
    }
}
