import AppKit
import SwiftUI
import WebKit

/// Shows the peek's web view in an AppKit container. The container, parent of the web view in the responder
/// chain, receives `cancelOperation:` when the page has not kept ⎋ (or ⌘.): the peek closes. The web view is only
/// added at creation: when it leaves for the card (“Open as Tab”), the container never takes it back.
struct PeekWebHost: NSViewRepresentable {
    let webView: WKWebView
    let onCancel: () -> Void

    func makeNSView(context _: Context) -> PeekWebContainer {
        let container = PeekWebContainer(webView: webView)
        container.onCancel = onCancel
        return container
    }

    func updateNSView(_ container: PeekWebContainer, context _: Context) {
        container.onCancel = onCancel
    }
}

/// AppKit parent of the peek's web view.
final class PeekWebContainer: NSView {
    let webView: WKWebView
    var onCancel: (() -> Void)?
    /// The page takes keyboard focus only once, at the first appearance.
    private var wantsFocus = true

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        addSubview(webView)
        webView.frame = bounds
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// The web view follows the container's size as long as it is in it (without touching its `autoresizingMask`,
    /// which the card manages once it has received it).
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if webView.superview === self {
            webView.frame = bounds
        }
    }

    /// On appearance, the peek's page takes keyboard focus from the originating page (or from nobody), never from
    /// a field.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard wantsFocus, let window, webView.superview === self else {
            return
        }
        wantsFocus = false
        if window.firstResponder === window || window.firstResponder is WKWebView {
            window.makeFirstResponder(webView)
        }
    }

    /// ⎋ or ⌘. that the page did not keep.
    override func cancelOperation(_: Any?) {
        onCancel?()
    }
}
