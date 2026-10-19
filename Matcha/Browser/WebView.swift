import SwiftUI
import WebKit

/// Displays a tab's web view in SwiftUI.
///
/// The view belongs to the tab: it is never recreated here. To switch tabs or after the tab is reloaded, display
/// another instance with `.id(ObjectIdentifier(webView))`, so that SwiftUI calls `makeNSView` again instead of reusing
/// the old view.
struct WebView: NSViewRepresentable {
    let webView: WKWebView
    /// Recipient of the sidebar items dropped on the page (split view); nil: refused.
    var sidebarDropTarget: (any SidebarItemDropTarget)?

    func makeNSView(context _: Context) -> WKWebView {
        (webView as? BrowserWebView)?.sidebarDropTarget = sidebarDropTarget
        return webView
    }

    func updateNSView(_ webView: WKWebView, context _: Context) {
        (webView as? BrowserWebView)?.sidebarDropTarget = sidebarDropTarget
    }
}
