import OSLog
import WebKit

/// Termination of a page's process (task 5.7): crash, or process stopped by the system (memory). Visible page
/// (selected tab or pane of its split in the displayed Space of an open window, Peek, mini window): reloaded right
/// away; hidden: reloaded when it is shown; repeated terminations: a message in the page, which is only reloaded by
/// the user. Rules: `PageCrashPolicy`; what the tab does: `BrowserTab+Crash`.
extension NavigationCoordinator {
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let tabHost, let page = tabHost.page(for: webView) else {
            Logger.browser.notice("Process of an unknown page terminated")
            return
        }
        let terminations = page.crash.processDidTerminate(at: now())
        let action = PageCrashPolicy.action(isVisible: tabHost.isVisible(page), recentTerminations: terminations)
        // Never the address: only the host.
        let host = page.url?.host() ?? "?"
        let window = Int(PageCrashCounter.window)
        Logger.browser.error("""
        Page process terminated (\(host, privacy: .private)): \(terminations, privacy: .public) times in \
        \(window, privacy: .public) s, \(action.rawValue, privacy: .public)
        """)
        page.webContentProcessDidTerminate(action)
    }
}
