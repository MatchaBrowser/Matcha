import AppKit
import WebKit

/// What needs to be known about a navigation request to decide what to do with it.
nonisolated struct NavigationRequest: Sendable {
    var url: URL?
    var navigationType: WKNavigationType
    var modifierFlags: NSEvent.ModifierFlags
    /// Mouse buttons, as a mask (checked with WebKit): 1 left (and Return on a link), 2 right,
    /// 4 middle, 0 none (click simulated by the page).
    var buttonNumber: Int
    /// True if the navigation targets the main frame or a new window, false for a subframe.
    var targetsMainFrame: Bool
    /// True if the main page asks for it (or the app), false for a frame inside it (`sourceFrame`, review WB1).
    var isFromMainFrame = true
    /// True if the web view can load this scheme (http, https, about, data, blob, registered scheme…).
    var isSchemeHandledByWebView: Bool
    /// True if the navigation asks for a new window (`target=_blank`, `window.open`): no target frame.
    var opensNewWindow = false
    /// Address of the document displayed by the web view, never the one being loaded (review WB1): anchor in the
    /// same page, link to another site.
    var pageURL: URL?
    /// True if the page asks for a download (`download` link): the navigation becomes a download.
    var shouldPerformDownload = false
    /// Web view the navigation starts from.
    var source = NavigationSource.tab
    /// True if links to another site open in Peek: favorite or pinned tab, setting enabled.
    var opensOtherSitesInPeek = false
}

/// Web view a navigation starts from.
nonisolated enum NavigationSource: Sendable {
    /// A tab of the sidebar.
    case tab
    /// Peek (task 4.4).
    case peek
    /// A web view this tab manager does not display, or the page of a mini window (task 4.5): a Shift-click stays a
    /// click there.
    case other
}

/// Outcome of a navigation request.
nonisolated enum NavigationDecision: Equatable, Sendable {
    /// WebKit carries on with the navigation.
    case allow
    /// The navigation is cancelled with no other effect.
    case cancel
    /// Cancelled, then the URL is handed to the app that handles it (Mail, Phone, Zoom…).
    case openExternally(URL)
    /// Cancelled, then the URL is opened in a new tab.
    case openInNewTab(URL, inBackground: Bool)
    /// Cancelled, then the URL is opened in Peek; from Peek, it loads there (task 4.4).
    case openInPeek(URL)
    /// The navigation becomes a download (task 5.1).
    case download
}

/// Navigation rules of the web views, with no dependency on the UI.
nonisolated enum NavigationPolicy {
    static let leftMouseButton = 1
    static let middleMouseButton = 4
    /// Schemes never opened by the app in a new tab or in Peek: their content depends on the page that contains them.
    static let schemesKeptInPlace: Set<String> = ["about", "blob", "data", "javascript"]
    static let webSchemes: Set<String> = ["http", "https"]
    /// Schemes never handed to another app, even with the user's consent (audit W2, review WB4): they mount a file
    /// share or open a remote session in the Finder, Terminal or Screen Sharing, behind a link whose text can pass for a
    /// web address. FTP included: WebKit no longer loads it, the Finder would mount the server.
    static let refusedSchemes: Set<String> = ["afp", "cifs", "ftp", "ftps", "nfs", "sftp", "smb", "ssh", "telnet", "vnc", "x-man-page"]
    /// Schemes a choice in the page's menu opens at once (review WB4); any other app waits in the page's banner.
    static let schemesOpenedFromMenu: Set<String> = ["mailto", "tel"]
    private static let linkModifiers: NSEvent.ModifierFlags = [.shift, .command, .option, .control]

    static func decide(_ request: NavigationRequest) -> NavigationDecision {
        guard let url = request.url else {
            return .allow
        }
        if !request.isSchemeHandledByWebView {
            // A subframe (ad…) is not allowed to launch another app, even through the main frame or a new window.
            let mayOpen = request.targetsMainFrame && request.isFromMainFrame && !isRefused(url)
            return mayOpen ? .openExternally(url) : .cancel
        }
        // `download` link: downloaded whatever the click (⌘-click, Shift-click); a tab or Peek would stay empty.
        if request.shouldPerformDownload {
            return .download
        }
        guard request.navigationType == .linkActivated, opensElsewhere(url, from: request.pageURL) else {
            return .allow
        }
        let modifiers = request.modifierFlags.intersection(linkModifiers)
        if modifiers.contains(.command) || request.buttonNumber == middleMouseButton {
            return .openInNewTab(url, inBackground: !modifiers.contains(.shift))
        }
        switch request.source {
        case .peek:
            // In Peek, browsing happens in place, even for a link that would open a window.
            return request.opensNewWindow ? .openInPeek(url) : .allow
        case .other:
            return .allow
        case .tab:
            return peekDecision(for: request, url: url, modifiers: modifiers)
        }
    }

    /// True if a navigation to the source viewer `url` (`matcha-source:`) comes from the app (review WB3): in the main
    /// frame, the load the user asked for in this tab (“View Page Source”, address bar, restored tab), a reload of the
    /// displayed viewer, or a move in the tab's history. Never a page's link, script, window or redirection: the viewer
    /// sends its request with the profile's cookies, and its address would be authorized at the next launch.
    static func allowsSourceViewer(_ url: URL, type: WKNavigationType, targetsMainFrame: Bool, requested: URL?, displayed: URL?) -> Bool {
        guard targetsMainFrame else {
            return false
        }
        switch type {
        case .backForward:
            return true
        case .reload:
            return url == displayed
        default:
            return url == requested
        }
    }

    static func isRefused(_ url: URL) -> Bool {
        refusedSchemes.contains(url.scheme?.lowercased() ?? "")
    }

    /// True if the app itself may load the link in a new tab or in Peek (audit W6): a web address, or a link to a page
    /// of the same kind as the displayed one (a local file from a local file). Anything else (`data:`, `blob:`, a local
    /// file linked from a website…) stays a plain click, which WebKit decides in place: the app's own loads skip
    /// WebKit's rules, and a local file would read its whole folder.
    static func opensElsewhere(_ url: URL, from page: URL?) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if webSchemes.contains(scheme) {
            return true
        }
        return !schemesKeptInPlace.contains(scheme) && page?.scheme?.lowercased() == scheme
    }

    /// Shift-click (except an anchor of the displayed page), and a link from a favorite or pinned tab to another site
    /// if the setting asks for it (left click without a key: never a click simulated by the page).
    private static func peekDecision(for request: NavigationRequest, url: URL, modifiers: NSEvent.ModifierFlags) -> NavigationDecision {
        if modifiers == .shift {
            return isAnchorOfShownPage(url, request) ? .allow : .openInPeek(url)
        }
        guard modifiers.isEmpty, request.buttonNumber == leftMouseButton, request.opensOtherSitesInPeek,
              request.targetsMainFrame, let page = request.pageURL, SiteDomain.isCrossSite(from: page, to: url)
        else {
            return .allow
        }
        return .openInPeek(url)
    }

    private static func isAnchorOfShownPage(_ url: URL, _ request: NavigationRequest) -> Bool {
        guard !request.opensNewWindow, request.targetsMainFrame, url.fragment != nil, let page = request.pageURL else {
            return false
        }
        return removingFragment(url) == removingFragment(page)
    }

    private static func removingFragment(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url
    }
}
