import AppKit
import WebKit

/// What owns a tab seen by extensions (task 6.3): what is needed to act on it (activate it, close it, pin it, set its
/// zoom).
@MainActor
enum ExtensionTabOwner {
    /// Sidebar tab of a Space of a browser window; for a favorite, the Space that holds it.
    case space(SpaceSession, WindowModel)
    /// Tab of a window of its own tabs (a detached tab, outside any Space).
    case window(WindowModel)
    /// Page of the Peek (task 4.4) open in the displayed Space.
    case peek(SpaceSession, WindowModel)
    /// Page of a mini window (task 4.5).
    case miniWindow(MiniWindowController, MiniWindowManager)
    /// Page of a sign-in window (task 5.8).
    case popupWindow(PopupWindowController, PopupWindowManager)

    /// Per-site zoom of the page (task 5.4).
    var siteZooms: SiteZoomStore? {
        switch self {
        case let .space(space, _), let .peek(space, _): space.tabManager.siteZooms
        case let .window(model): model.tabManager.siteZooms
        case let .miniWindow(_, manager): manager.siteZooms
        case let .popupWindow(_, manager): manager.siteZooms
        }
    }
}

/// What is behind a window seen by extensions (task 6.3).
@MainActor
enum ExtensionWindowOwner {
    /// Browser window (main or private): the tabs of all its Spaces.
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

    /// Mini windows and sign-in windows have only one page, with no tab bar: “popup” windows.
    var windowType: WKWebExtension.WindowType {
        switch self {
        case .browser: .normal
        case .miniWindow, .popupWindow: .popup
        }
    }

    /// A mini window is never private; a sign-in window is private when its session is.
    var isPrivate: Bool {
        switch self {
        case let .browser(model, _): model.session.isPrivate
        case .miniWindow: false
        case let .popupWindow(_, manager): manager.isPrivate
        }
    }
}
