import Foundation
import WebKit

/// Load state, displayed title and navigation commands of the page (buttons, menus, shortcuts).
extension BrowserTab {
    /// The page goes: its permission requests are denied, its sheets end (review IU15).
    func endPageRequests() {
        permissionPrompts.denyAll()
        pageDialogs.endSheets()
    }

    var isLoaded: Bool {
        webView != nil
    }

    /// Displayed as loaded in the sidebar (full title, close button): web view present, or put to sleep to save
    /// memory, which must not change anything in the display (task 5.6).
    var appearsLoaded: Bool {
        webView != nil || suspension.isSuspended
    }

    /// The schemes of `urls` that a handler of `configuration` serves (the source viewer).
    static func servedSchemes(of configuration: WKWebViewConfiguration, among urls: [URL?]) -> Set<String> {
        Set(urls.compactMap { $0?.scheme?.lowercased() }.filter { configuration.urlSchemeHandler(forURLScheme: $0) != nil })
    }

    /// Title to display: the page's title, otherwise the host of the address shown, otherwise “New Tab”; never the host
    /// of a load that isn't displayed yet (review TR1).
    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        if let host = displayedURL?.host(), !host.isEmpty {
            return host
        }
        return displayedURL?.absoluteString ?? String(localized: "New Tab")
    }

    /// Navigation commands lead away from the page woken from sleep: no more snapshot on top of it; a crashed page
    /// (task 5.7) leaves its message; a failed load (audit K5) goes away, and “Back” returns to the page under it.
    func goBack() {
        if leaveLoadFailure() {
            return
        }
        suspension.endRestoring()
        crash.pageWillNavigate()
        webView?.goBack()
    }

    func goForward() {
        loadFailure.clear()
        suspension.endRestoring()
        crash.pageWillNavigate()
        webView?.goForward()
    }

    /// After the process terminated (task 5.7: automatic reload, the message's button, ⌘R), reloading is not a new
    /// history visit, like waking from sleep; a page terminated before it displayed anything (nothing to reload) loads
    /// its address.
    func reload() {
        if retryFailedLoad() {
            return
        }
        suspension.endRestoring()
        guard crash.isRecovering else {
            webView?.reload()
            return
        }
        crash.pageWillNavigate()
        history.pageWillResume(url: url)
        if webView?.reload() == nil, let url {
            load(url)
        }
    }

    /// ⌥⌘R: reloads without the cache. A failed load or a crashed page reloads as with ⌘R.
    func reloadFromOrigin() {
        guard let webView, !crash.isRecovering else {
            reload()
            return
        }
        if retryFailedLoad() {
            return
        }
        suspension.endRestoring()
        webView.reloadFromOrigin()
    }

    func stop() {
        webView?.stopLoading()
    }
}
