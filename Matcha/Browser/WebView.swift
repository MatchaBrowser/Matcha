import SwiftUI
import WebKit

/// Affiche la vue web d'un onglet dans SwiftUI.
///
/// La vue appartient à l'onglet : on ne la recrée jamais ici. Pour changer d'onglet ou après un
/// rechargement de l'onglet, afficher une autre instance avec `.id(ObjectIdentifier(webView))`, afin
/// que SwiftUI appelle de nouveau `makeNSView` au lieu de réutiliser l'ancienne vue.
struct WebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context _: Context) -> WKWebView {
        webView
    }

    func updateNSView(_: WKWebView, context _: Context) {}
}
