import AppKit
import SwiftUI
import WebKit

/// Affiche la vue web de l'aperçu dans un conteneur AppKit. Le conteneur, parent de la vue web dans la
/// chaîne des répondeurs, reçoit `cancelOperation:` quand la page n'a pas gardé ⎋ (ni ⌘.) : l'aperçu se
/// ferme. La vue web n'est ajoutée qu'à la création : quand elle part dans la carte (« Ouvrir en onglet »),
/// le conteneur ne la reprend jamais.
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

/// Parent AppKit de la vue web de l'aperçu.
final class PeekWebContainer: NSView {
    let webView: WKWebView
    var onCancel: (() -> Void)?
    /// La page prend le clavier une seule fois, à la première apparition.
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

    /// La vue web suit la taille du conteneur tant qu'elle y est (sans toucher à son `autoresizingMask`,
    /// que la carte gère une fois qu'elle l'a reçue).
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if webView.superview === self {
            webView.frame = bounds
        }
    }

    /// À l'apparition, la page de l'aperçu prend le clavier à la page d'origine (ou à personne), jamais à un champ.
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

    /// ⎋ ou ⌘. que la page n'a pas gardés.
    override func cancelOperation(_: Any?) {
        onCancel?()
    }
}
