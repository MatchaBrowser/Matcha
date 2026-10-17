import AppKit
import SwiftUI
import WebKit

/// Vue AppKit qui porte la vue web d'une mini-fenêtre. Elle seule l'ajoute et la retire : SwiftUI ne manipule
/// jamais la vue web, qui peut ainsi passer dans un Space sans rechargement (« Ouvrir dans le Space ») : elle est
/// retirée ici avant que la carte de la fenêtre principale ne l'affiche, et n'a jamais deux parents.
final class MiniWebViewContainer: NSView {
    private(set) weak var webView: WKWebView?

    /// Montre `webView`, à la taille du conteneur.
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

    /// Retire la vue web (remise à un Space, fermeture).
    func detach() {
        guard let webView else {
            return
        }
        if webView.superview === self {
            webView.removeFromSuperview()
        }
        self.webView = nil
    }

    /// La vue web suit la taille du conteneur tant qu'elle y est, sans toucher à son `autoresizingMask`, que
    /// la carte gère une fois qu'elle l'a reçue (même règle que l'aperçu, tâche 4.4).
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

/// Le conteneur dans SwiftUI : toujours le même, jamais recréé.
struct MiniWebViewContainerView: NSViewRepresentable {
    let container: MiniWebViewContainer

    func makeNSView(context _: Context) -> MiniWebViewContainer {
        container
    }

    func updateNSView(_: MiniWebViewContainer, context _: Context) {}
}
