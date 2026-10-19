import WebKit

/// History (task 5.5): the visit is recorded at the end of loading (`didFinish`, in the main file); a failed load
/// leaves none, and a changed address waiting to be recorded is forgotten. The address shown is the displayed page's
/// again (audit W4). The reload of a page woken from sleep
/// (task 5.6) or whose process stopped (5.7) is also ended. The blocker (task 6.2) returns to the state of the page
/// still displayed.
extension NavigationCoordinator {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: any Error) {
        navigationDidFail(in: webView)
        provisionalNavigationDidFail(in: webView, error: error)
    }

    func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError _: any Error) {
        navigationDidFail(in: webView)
    }

    private func navigationDidFail(in webView: WKWebView) {
        guard let page = tabHost?.page(for: webView) else {
            return
        }
        page.history.navigationDidFail()
        page.suspension.endRestoring()
        page.crash.end()
        page.documentDidChange()
    }
}
