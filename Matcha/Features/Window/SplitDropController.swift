import AppKit
import Foundation

/// Drop on the card's pages: a tab dragged from the sidebar and dropped on the left or right edge of a pane joins the
/// split on that side. During hovering, only what is displayed counts; the dragged item is read only on drop. The card
/// reconfigures it on each render.
@MainActor
final class SplitDropController: SidebarItemDropTarget {
    /// Displayed tabs, from left to right.
    var panes: [BrowserTab] = []
    /// Widths of the panes, from left to right.
    var widths: [Double] = []
    /// Width hidden by the floating sidebar to the left of the panes: no drop underneath.
    var leadingInset = 0.0
    /// Can what is displayed take one more pane?
    var canTakeTab = false
    var onTargetChange: (SplitDropTarget?) -> Void = { _ in }
    /// True if the tab joined the split; false refuses the drop (the item goes back to its place).
    var onDrop: (UUID, SplitDropTarget) -> Bool = { _, _ in false }

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
        // Only a tab joins a split; a folder or a split dropped here is refused.
        guard let target,
              let data = info.draggingPasteboard.data(forType: BrowserWebView.sidebarItemType),
              case let .tab(id)? = SidebarDragItem(data: data)
        else {
            return false
        }
        return onDrop(id, target)
    }

    /// Edge of the pane of `webView` under the pointer, outside the floating sidebar.
    private func dropTarget(for info: any NSDraggingInfo, over webView: BrowserWebView) -> SplitDropTarget? {
        guard canTakeTab, let index = panes.firstIndex(where: { $0.webView === webView }) else {
            return nil
        }
        let offset = webView.convert(info.draggingLocation, from: nil).x
        return SplitGeometry.dropTarget(atX: offset, inPane: index, widths: widths, leadingInset: leadingInset)
    }

    private func setTarget(_ target: SplitDropTarget?) {
        guard target != current else {
            return
        }
        current = target
        onTargetChange(target)
    }
}
