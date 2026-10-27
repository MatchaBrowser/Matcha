import AppKit
import UniformTypeIdentifiers
import WebKit

/// Receives sidebar items dragged onto a page (split view).
@MainActor
protocol SidebarItemDropTarget: AnyObject {
    /// Operation offered while hovering over `webView`; `[]` to refuse.
    func sidebarItemDragUpdated(_ info: any NSDraggingInfo, over webView: BrowserWebView) -> NSDragOperation
    /// The drag leaves the page or ends.
    func sidebarItemDragExited()
    /// Drop on `webView`; false if it is refused.
    func sidebarItemDropped(_ info: any NSDraggingInfo, on webView: BrowserWebView) -> Bool
}

/// Web view of Matcha's tabs.
///
/// ⌃⇥ and ⌃⇧⇥ switch tabs, as in Safari: the app menu goes before WebKit, which would use them to move the focus
/// within the page. ⌘= is offered to the menu as ⌘+ (“Zoom In”, task 5.4).
///
/// An item dragged from the sidebar never reaches the page: the SwiftUI drag also carries file promises, which WebKit
/// is registered for, so the page would receive any drag that hovers over it. Those carrying the sidebar's private
/// type go to `sidebarDropTarget`, or are refused.
///
/// Context menu of the page (task 5.9): `BrowserWebView+PageMenu`.
final class BrowserWebView: WKWebView {
    static let sidebarItemType = NSPasteboard.PasteboardType(UTType.matchaSidebarItem.identifier)

    /// Recipient of the sidebar items dropped on this page; nil: refused.
    weak var sidebarDropTarget: (any SidebarItemDropTarget)?
    /// Context menu choice waiting for the window WebKit opens for it, read by `NavigationCoordinator`.
    var pageMenuIntent = PendingPageMenuIntent()
    /// Sound of the tab this web view belongs to (task 5.10), recipient of the messages of the sound script; nil once
    /// the view is released by its tab.
    weak var audio: PageAudio?
    /// Translation of the page of this web view while it is translated (task 9.2), recipient of the messages of the
    /// translation script; set and cleared by the translation itself.
    weak var translation: PageTranslation?
    /// Translation sessions of the window showing this view (task 9.3), for “Translate to …” of the page menu; set
    /// by that window.
    weak var translationHost: (any PageTranslationHosting)?
    /// Recipient of the messages of the notification script: the tab's navigation delegate (review CO1).
    weak var notifications: (any PageNotificationReceiving)?

    /// Inspectable according to the developer tools setting, followed as long as the view exists.
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        WebInspection.apply(to: self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(webInspectionDidChange),
            name: WebInspection.didChange,
            object: nil,
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func webInspectionDidChange() {
        WebInspection.apply(to: self)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        rewritePageMenu(menu)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard Self.carriesSidebarItem(sender) else {
            return super.draggingEntered(sender)
        }
        return sidebarDropTarget?.sidebarItemDragUpdated(sender, over: self) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard Self.carriesSidebarItem(sender) else {
            return super.draggingUpdated(sender)
        }
        return sidebarDropTarget?.sidebarItemDragUpdated(sender, over: self) ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        guard let sender, Self.carriesSidebarItem(sender) else {
            super.draggingExited(sender)
            return
        }
        sidebarDropTarget?.sidebarItemDragExited()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard Self.carriesSidebarItem(sender) else {
            return super.prepareForDragOperation(sender)
        }
        return sidebarDropTarget != nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard Self.carriesSidebarItem(sender) else {
            return super.performDragOperation(sender)
        }
        return sidebarDropTarget?.sidebarItemDropped(sender, on: self) ?? false
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        guard let sender, Self.carriesSidebarItem(sender) else {
            super.concludeDragOperation(sender)
            return
        }
        sidebarDropTarget?.sidebarItemDragExited()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        guard Self.carriesSidebarItem(sender) else {
            super.draggingEnded(sender)
            return
        }
        sidebarDropTarget?.sidebarItemDragExited()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isTabSwitch(event), NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        // ⌘=: “Zoom In” (⌘+); without this, the menu would not recognize it.
        if let zoomIn = ZoomKeyAlias.zoomInEvent(for: event), NSApp.mainMenu?.performKeyEquivalent(with: zoomIn) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// ⌃⇥ or ⌃⇧⇥, without ⌘ or ⌥.
    private static func isTabSwitch(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.type == .keyDown
            && (event.specialKey == .tab || event.specialKey == .backTab)
            && flags.contains(.control)
            && flags.isDisjoint(with: [.command, .option])
    }

    /// Does the drag carry a sidebar item? Only the types are read, never the data.
    private static func carriesSidebarItem(_ info: any NSDraggingInfo) -> Bool {
        info.draggingPasteboard.types?.contains(sidebarItemType) == true
    }
}
