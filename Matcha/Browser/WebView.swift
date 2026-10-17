import SwiftUI
import WebKit

/// Affiche la vue web d'un onglet dans SwiftUI.
///
/// La vue appartient à l'onglet : on ne la recrée jamais ici. Pour changer d'onglet ou après un
/// rechargement de l'onglet, afficher une autre instance avec `.id(ObjectIdentifier(webView))`, afin
/// que SwiftUI appelle de nouveau `makeNSView` au lieu de réutiliser l'ancienne vue.
struct WebView: NSViewRepresentable {
    let webView: WKWebView
    /// Destinataire des éléments de la barre lâchés sur la page (split view) ; nil : refusés.
    var sidebarDropTarget: (any SidebarItemDropTarget)?

    func makeNSView(context _: Context) -> WKWebView {
        (webView as? BrowserWebView)?.sidebarDropTarget = sidebarDropTarget
        return webView
    }

    func updateNSView(_ webView: WKWebView, context _: Context) {
        (webView as? BrowserWebView)?.sidebarDropTarget = sidebarDropTarget
    }
}
