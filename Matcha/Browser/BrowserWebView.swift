import AppKit
import UniformTypeIdentifiers
import WebKit

/// Reçoit les éléments de la barre glissés sur une page (split view).
@MainActor
protocol SidebarItemDropTarget: AnyObject {
    /// Opération proposée pendant le survol de `webView` ; `[]` pour refuser.
    func sidebarItemDragUpdated(_ info: any NSDraggingInfo, over webView: BrowserWebView) -> NSDragOperation
    /// Le glisser quitte la page ou se termine.
    func sidebarItemDragExited()
    /// Dépôt sur `webView` ; faux s'il est refusé.
    func sidebarItemDropped(_ info: any NSDraggingInfo, on webView: BrowserWebView) -> Bool
}

/// Vue web des onglets de Matcha.
///
/// ⌃⇥ et ⌃⇧⇥ changent d'onglet, comme dans Safari : le menu de l'app passe avant WebKit, qui s'en servirait
/// pour déplacer le focus dans la page. ⌘= est proposé au menu comme ⌘+ (« Zoom avant », tâche 5.4).
///
/// Un élément glissé depuis la barre n'atteint jamais la page : le glisser de SwiftUI porte aussi des promesses
/// de fichier, pour lesquelles WebKit est inscrit, si bien que la page recevrait tout glisser qui la survole.
/// Ceux qui portent le type privé de la barre vont à `sidebarDropTarget`, ou sont refusés.
///
/// Menu contextuel de la page (tâche 5.9) : `BrowserWebView+PageMenu`.
final class BrowserWebView: WKWebView {
    static let sidebarItemType = NSPasteboard.PasteboardType(UTType.matchaSidebarItem.identifier)

    /// Destinataire des éléments de la barre lâchés sur cette page ; nil : refusés.
    weak var sidebarDropTarget: (any SidebarItemDropTarget)?
    /// Choix du menu contextuel en attente de la fenêtre que WebKit ouvre pour lui, lu par `NavigationCoordinator`.
    var pageMenuIntent = PendingPageMenuIntent()

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
        // ⌘= : « Zoom avant » (⌘+) ; sans lui, le menu ne le reconnaîtrait pas.
        if let zoomIn = ZoomKeyAlias.zoomInEvent(for: event), NSApp.mainMenu?.performKeyEquivalent(with: zoomIn) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// ⌃⇥ ou ⌃⇧⇥, sans ⌘ ni ⌥.
    private static func isTabSwitch(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.type == .keyDown
            && (event.specialKey == .tab || event.specialKey == .backTab)
            && flags.contains(.control)
            && flags.isDisjoint(with: [.command, .option])
    }

    /// Le glisser porte-t-il un élément de la barre ? Seuls les types sont lus, jamais les données.
    private static func carriesSidebarItem(_ info: any NSDraggingInfo) -> Bool {
        info.draggingPasteboard.types?.contains(sidebarItemType) == true
    }
}
