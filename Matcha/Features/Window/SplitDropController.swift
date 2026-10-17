import AppKit
import Foundation

/// Dépôt sur les pages de la carte : un onglet glissé depuis la barre et lâché sur le bord gauche ou droit d'un
/// panneau rejoint le split de ce côté. Pendant le survol, seul compte ce qui est affiché ; l'élément glissé
/// n'est lu qu'au dépôt. La carte le reconfigure à chaque affichage.
@MainActor
final class SplitDropController: SidebarItemDropTarget {
    /// Onglets affichés, de gauche à droite.
    var panes: [BrowserTab] = []
    /// Largeurs des panneaux, de gauche à droite.
    var widths: [Double] = []
    /// Largeur cachée par la barre flottante à gauche des panneaux : pas de dépôt dessous.
    var leadingInset = 0.0
    /// Ce qui est affiché peut-il prendre un panneau de plus ?
    var canTakeTab = false
    var onTargetChange: (SplitDropTarget?) -> Void = { _ in }
    var onDrop: (UUID, SplitDropTarget) -> Void = { _, _ in }

    private var current: SplitDropTarget?

    func sidebarItemDragUpdated(_ info: any NSDraggingInfo, over webView: BrowserWebView) -> NSDragOperation {
        let target = dropTarget(for: info, over: webView)
        setTarget(target)
        guard target != nil else {
            return []
        }
        let allowed = info.draggingSourceOperationMask
        for operation: NSDragOperation in [.move, .copy, .generic] where allowed.contains(operation) {
            return operation
        }
        return []
    }

    func sidebarItemDragExited() {
        setTarget(nil)
    }

    func sidebarItemDropped(_ info: any NSDraggingInfo, on webView: BrowserWebView) -> Bool {
        let target = dropTarget(for: info, over: webView)
        setTarget(nil)
        // Seul un onglet rejoint un split ; un dossier ou un split lâché ici est refusé.
        guard let target,
              let data = info.draggingPasteboard.data(forType: BrowserWebView.sidebarItemType),
              case let .tab(id)? = SidebarDragItem(data: data)
        else {
            return false
        }
        onDrop(id, target)
        return true
    }

    /// Bord du panneau de `webView` sous le pointeur, hors de la barre flottante.
    private func dropTarget(for info: any NSDraggingInfo, over webView: BrowserWebView) -> SplitDropTarget? {
        guard canTakeTab,
              let index = panes.firstIndex(where: { $0.webView === webView }),
              widths.indices.contains(index)
        else {
            return nil
        }
        let position = SplitGeometry.paneOrigins(widths: widths)[index] + webView.convert(info.draggingLocation, from: nil).x
        guard position >= leadingInset else {
            return nil
        }
        return SplitGeometry.dropTarget(atX: position, widths: widths)
    }

    private func setTarget(_ target: SplitDropTarget?) {
        guard target != current else {
            return
        }
        current = target
        onTargetChange(target)
    }
}
