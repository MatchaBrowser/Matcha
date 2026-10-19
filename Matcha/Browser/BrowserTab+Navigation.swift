import Foundation
import WebKit

/// Displayed title and navigation commands of the page (buttons, menus, shortcuts).
extension BrowserTab {
    /// Title to display: the page's title, otherwise the host, otherwise “New Tab”.
    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        if let host = url?.host(), !host.isEmpty {
            return host
        }
        return url?.absoluteString ?? String(localized: "New Tab")
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
