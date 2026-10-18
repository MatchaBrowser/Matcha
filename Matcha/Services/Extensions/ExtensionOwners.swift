import AppKit
import WebKit

/// Ce qui possède un onglet vu par les extensions (tâche 6.3) : de quoi agir sur lui (l'activer, le fermer, l'épingler,
/// régler son zoom).
@MainActor
enum ExtensionTabOwner {
    /// Onglet rangé d'un Space d'une fenêtre de navigation ; pour un favori, le Space qui le tient.
    case space(SpaceSession, WindowModel)
    /// Page de l'aperçu (Peek, tâche 4.4) ouvert dans le Space affiché.
    case peek(SpaceSession, WindowModel)
    /// Page d'une mini-fenêtre (tâche 4.5).
    case miniWindow(MiniWindowController, MiniWindowManager)
    /// Page d'une fenêtre de connexion (tâche 5.8).
    case popupWindow(PopupWindowController, PopupWindowManager)

    /// Zoom par site de la page (tâche 5.4).
    var siteZooms: SiteZoomStore? {
        switch self {
        case let .space(space, _), let .peek(space, _): space.tabManager.siteZooms
        case let .miniWindow(_, manager): manager.siteZooms
        case let .popupWindow(_, manager): manager.siteZooms
        }
    }
}

/// Ce qui est derrière une fenêtre vue par les extensions (tâche 6.3).
@MainActor
enum ExtensionWindowOwner {
    /// Fenêtre de navigation (principale ou privée) : les onglets de tous ses Spaces.
    case browser(WindowModel, NSWindow?)
    case miniWindow(MiniWindowController)
    case popupWindow(PopupWindowController, PopupWindowManager)

    var nsWindow: NSWindow? {
        switch self {
        case let .browser(_, window): window
        case let .miniWindow(controller): controller.panel
        case let .popupWindow(controller, _): controller.window
        }
    }

    /// Mini-fenêtres et fenêtres de connexion n'ont qu'une page, sans barre d'onglets : des fenêtres « popup ».
    var windowType: WKWebExtension.WindowType {
        switch self {
        case .browser: .normal
        case .miniWindow, .popupWindow: .popup
        }
    }

    /// Une mini-fenêtre n'est jamais privée ; une fenêtre de connexion l'est avec sa session.
    var isPrivate: Bool {
        switch self {
        case let .browser(model, _): model.session.isPrivate
        case .miniWindow: false
        case let .popupWindow(_, manager): manager.isPrivate
        }
    }
}
