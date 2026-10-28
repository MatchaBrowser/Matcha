import WebKit

extension BrowserTab {
    /// A new web view for the tab (`makeWebViewIfNeeded`): its configuration, gestures, delegates, zoom and sound.
    func newWebView() -> BrowserWebView {
        let webView = BrowserWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.notifications = delegate
        webView.pageZoom = pageZoom
        webView.audio = audio
        return webView
    }
}
