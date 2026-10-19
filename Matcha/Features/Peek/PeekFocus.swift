import AppKit
import WebKit

/// Gives keyboard focus back to the peek's web view once it has moved into the card: AppKit removes the first
/// responder from a view that changes parent.
@MainActor
enum PeekFocus {
    /// Waits (one second at most) for `webView` to be in a window under a parent other than `oldHost`, then gives
    /// it keyboard focus if nobody took it in the meantime.
    static func focus(_ webView: WKWebView, awayFrom oldHost: NSView?) {
        Task { @MainActor [weak webView, weak oldHost] in
            for _ in 0 ..< 20 {
                guard let webView else {
                    return
                }
                if let window = webView.window, let parent = webView.superview, parent !== oldHost {
                    if window.firstResponder === window {
                        window.makeFirstResponder(webView)
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
