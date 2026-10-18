import AppKit
import WebKit

/// Bulle d'une action d'extension (tâche 6.3) : la bulle toute prête de WebKit (`WKWebExtension.Action.popupPopover`,
/// vue web de la popup qui prend la taille de sa page ; la fermer libère la page), ancrée au bouton de l'extension
/// (`anchor`, tâche 6.5), sinon au coin haut droit du contenu de la fenêtre.
@MainActor
final class ExtensionPopupPresenter {
    /// Vue et rectangle (dans cette vue) sous lesquels montrer la bulle de `action` dans `window` ; nil : pas de bulle.
    var anchor: @MainActor (WKWebExtension.Action, NSWindow) -> (view: NSView, rect: CGRect)? = { _, window in
        ExtensionPopupPresenter.topTrailingAnchor(in: window)
    }

    /// Montre la bulle de `action` dans `window` ; faux sans popup, sans fenêtre ou sans ancre.
    func present(_ action: WKWebExtension.Action, in window: NSWindow?) -> Bool {
        guard let window, let popover = action.popupPopover, let (view, rect) = anchor(action, window) else {
            return false
        }
        // Sous le rectangle : son bord du bas, qui est `maxY` dans une vue retournée (SwiftUI).
        popover.show(relativeTo: rect, of: view, preferredEdge: view.isFlipped ? .maxY : .minY)
        return true
    }

    /// Petit rectangle près du coin haut droit du contenu de `window`.
    static func topTrailingAnchor(in window: NSWindow) -> (view: NSView, rect: CGRect)? {
        guard let view = window.contentView else {
            return nil
        }
        let bounds = view.bounds
        let size = CGSize(width: 24, height: 24)
        let top = view.isFlipped ? bounds.minY + 8 : bounds.maxY - 8 - size.height
        return (view, CGRect(origin: CGPoint(x: bounds.maxX - 16 - size.width, y: top), size: size))
    }
}
