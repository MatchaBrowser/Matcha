import AppKit
import SwiftUI
import WebKit

/// AppKit view that holds a mini window's web view. It alone adds and removes it: SwiftUI never manipulates the
/// web view, which can thus move into a Space without reloading (“Open in Space”): it is removed here before the
/// main window's card displays it, and never has two parents. The sign-in windows (task 5.8) use it too.
final class MiniWebViewContainer: NSView {
    private(set) weak var webView: WKWebView?

    /// Shows `webView`, at the container's size.
    func attach(_ webView: WKWebView) {
        guard webView.superview !== self else {
            return
        }
        self.webView?.removeFromSuperview()
        webView.removeFromSuperview()
        webView.frame = bounds
        addSubview(webView)
        self.webView = webView
    }

    /// Removes the web view (handed to a Space, closing).
    func detach() {
        guard let webView else {
            return
        }
        if webView.superview === self {
            webView.removeFromSuperview()
        }
        self.webView = nil
    }

    /// The web view follows the container's size while it is inside it, without touching its `autoresizingMask`,
    /// which the card manages once it has received it (same rule as Peek, task 4.4).
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitWebView()
    }

    override func layout() {
        super.layout()
        fitWebView()
    }

    private func fitWebView() {
        if let webView, webView.superview === self, webView.frame != bounds {
            webView.frame = bounds
        }
    }
}

/// The container in SwiftUI: always the same one, never recreated.
struct MiniWebViewContainerView: NSViewRepresentable {
    let container: MiniWebViewContainer

    func makeNSView(context _: Context) -> MiniWebViewContainer {
        container
    }

    func updateNSView(_: MiniWebViewContainer, context _: Context) {}
}
