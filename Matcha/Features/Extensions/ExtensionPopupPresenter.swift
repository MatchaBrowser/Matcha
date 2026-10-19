import AppKit
import WebKit

/// Popover of an extension action (task 6.3): WebKit's ready-made popover (`WKWebExtension.Action.popupPopover`, web
/// view of the popup that takes the size of its page; closing it releases the page), anchored to the extension's button
/// (`anchor`, task 6.5), otherwise to the top right corner of the window's content.
@MainActor
final class ExtensionPopupPresenter {
    /// View and rectangle (in that view) below which to show the popover of `action` in `window`; nil: no popover.
    var anchor: @MainActor (WKWebExtension.Action, NSWindow) -> (view: NSView, rect: CGRect)? = { _, window in
        ExtensionPopupPresenter.topTrailingAnchor(in: window)
    }

    /// Shows the popover of `action` in `window`; false without a popup, without a window or without an anchor.
    func present(_ action: WKWebExtension.Action, in window: NSWindow?) -> Bool {
        guard let window, let popover = action.popupPopover, let (view, rect) = anchor(action, window) else {
            return false
        }
        // Below the rectangle: its bottom edge, which is `maxY` in a flipped view (SwiftUI).
        popover.show(relativeTo: rect, of: view, preferredEdge: view.isFlipped ? .maxY : .minY)
        return true
    }

    /// Small rectangle near the top right corner of the content of `window`.
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
