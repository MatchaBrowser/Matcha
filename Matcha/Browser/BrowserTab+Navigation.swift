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
    /// (task 5.7) leaves its message.
    func goBack() {
        suspension.endRestoring()
        crash.pageWillNavigate()
        webView?.goBack()
    }

    func goForward() {
        suspension.endRestoring()
        crash.pageWillNavigate()
        webView?.goForward()
    }

    /// After the process terminated (task 5.7: automatic reload, the message's button, ⌘R), reloading is not a new
    /// history visit, like waking from sleep; a page terminated before it displayed anything (nothing to reload) loads
    /// its address.
    func reload() {
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

    func stop() {
        webView?.stopLoading()
    }
}
