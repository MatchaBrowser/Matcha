import SwiftUI
import WebKit

/// Displays a tab's web view in SwiftUI, in an AppKit container.
///
/// The view belongs to the tab: it is never recreated here. To switch tabs or after the tab is reloaded, display
/// another instance with `.id(ObjectIdentifier(webView))`, so that SwiftUI calls `makeNSView` again instead of reusing
/// the old view. The container takes the web view only at creation and gives it up only if it still holds it: when the
/// page goes to another window (several windows on a Space), the order in which the two windows update doesn't matter.
struct WebView: NSViewRepresentable {
    let webView: WKWebView
    /// Recipient of the sidebar items dropped on the page (split view); nil: refused.
    var sidebarDropTarget: (any SidebarItemDropTarget)?
    /// Translation sessions of the window, for the page menu (task 9.3).
    var translationHost: (any PageTranslationHosting)?

    func makeNSView(context _: Context) -> TabWebContainer {
        update(webView)
        return TabWebContainer(webView: webView)
    }

    func updateNSView(_: TabWebContainer, context _: Context) {
        update(webView)
    }

    private func update(_ webView: WKWebView) {
        (webView as? BrowserWebView)?.sidebarDropTarget = sidebarDropTarget
        (webView as? BrowserWebView)?.translationHost = translationHost
    }

    static func dismantleNSView(_ container: TabWebContainer, coordinator _: ()) {
        container.release()
    }
}

/// AppKit parent of a tab's web view in a card.
final class TabWebContainer: NSView {
    let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        webView.frame = bounds
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// Removes the web view if it is still here (not taken by another window, the peek or a mini window).
    func release() {
        if webView.superview === self {
            webView.removeFromSuperview()
        }
    }

    /// The web view follows the container's size as long as it is in it.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitWebView()
    }

    override func layout() {
        super.layout()
        fitWebView()
    }

    private func fitWebView() {
        if webView.superview === self, webView.frame != bounds {
            webView.frame = bounds
        }
    }
}
