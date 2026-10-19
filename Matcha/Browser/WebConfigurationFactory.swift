import WebKit

/// Builds the WebKit configuration shared by all web views, with the sound script (task 5.10), the source viewer and
/// the extension controller (task 6.3, private windows included: extensions only have access to them if the user
/// allows it). Each page has its own content controller (`pageConfiguration`): the blocker (task 6.2) sets or removes
/// its lists there page by page; WebKit injects the extensions' scripts into it. One for the app (`AppEnvironment`);
/// the tests make theirs, without extensions.
@MainActor
final class WebConfigurationFactory {
    /// Safari version announced to sites, so that they treat the app as Safari: the installed Safari's (audit H5).
    static let safariVersion = SafariVersion.announced(
        installed: SafariVersion.installed(),
        system: ProcessInfo.processInfo.operatingSystemVersion,
    )

    /// Content controllers already given to a page (`BrowserTab`).
    private static let pageControllers = NSHashTable<WKUserContentController>.weakObjects()

    /// Source viewer of the pages (`matcha-source:`).
    let pageSources: PageSourceSchemeHandler
    /// Hands each configuration to the extension controller; nil: no extensions.
    private let attachExtensions: (@MainActor (WKWebViewConfiguration) -> Void)?

    init(
        pageSources: PageSourceSchemeHandler = PageSourceSchemeHandler(),
        attachExtensions: (@MainActor (WKWebViewConfiguration) -> Void)? = nil,
    ) {
        self.pageSources = pageSources
        self.attachExtensions = attachExtensions
    }

    /// Suffix added by WebKit to its user agent.
    static var applicationNameForUserAgent: String {
        "Version/\(safariVersion) Safari/605.1.15"
    }

    func makeConfiguration(websiteDataStore: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.preferences.isElementFullscreenEnabled = true
        // Pop-up blocker (as in Safari): a page only opens a window or a tab right after a click or a key press.
        // WebKit's default on macOS lets scripts open as many as they want.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // An http address is tried in https first, then in http if that fails (audit W5; WebKit keeps the address as
        // requested by default).
        configuration.defaultWebpagePreferences.preferredHTTPSNavigationPolicy = .automaticFallbackToHTTP
        // Media with sound waits for a click, as with Safari's “Stop Media with Sound” (audit H5); silent media plays.
        configuration.mediaTypesRequiringUserActionForPlayback = .audio
        WebInspection.apply(to: configuration.preferences)
        configuration.applicationNameForUserAgent = Self.applicationNameForUserAgent
        configuration.userContentController = Self.makeUserContentController()
        // “View Page Source” (menu of a page).
        configuration.setURLSchemeHandler(pageSources, forURLScheme: PageSource.scheme)
        attachExtensions?(configuration)
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
