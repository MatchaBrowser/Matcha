import AppKit
import WebKit

/// Rend le clavier à la vue web de l'aperçu une fois passée dans la carte : AppKit retire le premier
/// répondant d'une vue qui change de parent.
@MainActor
enum PeekFocus {
    /// Attend (une seconde au plus) que `webView` soit dans une fenêtre sous un autre parent que `oldHost`,
    /// puis lui donne le clavier si personne ne l'a pris entre-temps.
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
