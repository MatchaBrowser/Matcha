import AppKit
import WebKit

/// A window as extensions see it (task 6.3): `WKWebExtensionWindow` adapter of a browser window, a mini window or a
/// sign-in window, designated by its identifier and looked up again in `ExtensionWindows`. One object per window,
/// always the same while it is open. Its type and whether it is private do not change (WebKit keeps them from the first
/// read). Not supported: changing its size or its state (minimized, full screen).
@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    let windowID: UUID
    let type: WKWebExtension.WindowType
    let isPrivate: Bool
    private weak var windows: ExtensionWindows?

    init(id: UUID, windows: ExtensionWindows, type: WKWebExtension.WindowType, isPrivate: Bool) {
        windowID = id
        self.windows = windows
        self.type = type
        self.isPrivate = isPrivate
    }

    var owner: ExtensionWindowOwner? {
        windows?.owner(ofWindow: windowID)
    }

    func tabs(for _: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        windows?.tabs(inWindow: windowID) ?? []
    }

    func activeTab(for _: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        windows?.activeTab(inWindow: windowID)
    }

    func windowType(for _: WKWebExtensionContext) -> WKWebExtension.WindowType {
        type
    }

    func windowState(for _: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = owner?.nsWindow else {
            return .normal
        }
        if window.isMiniaturized {
            return .minimized
        }
        return window.styleMask.contains(.fullScreen) ? .fullscreen : .normal
    }

    func isPrivate(for _: WKWebExtensionContext) -> Bool {
        isPrivate
    }

    func screenFrame(for _: WKWebExtensionContext) -> CGRect {
        (owner?.nsWindow?.screen ?? NSScreen.main)?.frame ?? .null
    }

    func frame(for _: WKWebExtensionContext) -> CGRect {
        owner?.nsWindow?.frame ?? .null
    }

    /// Brings the window to the front (out of the Dock included) and activates the app.
    func focus(for _: WKWebExtensionContext, completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        guard let window = owner?.nsWindow else {
            completionHandler(ExtensionError.notFound)
            return
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        completionHandler(nil)
    }

    /// A mini window or a sign-in window closes; a browser window does not: it carries all the Spaces (and a private
    /// window, all its browsing).
    func close(for _: WKWebExtensionContext, completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        switch owner {
        case let .miniWindow(controller):
            controller.close()
        case let .popupWindow(controller, _):
            controller.close()
        case .browser:
            completionHandler(ExtensionError.unsupported("Browser windows cannot be closed by extensions."))
            return
        case nil:
            completionHandler(ExtensionError.notFound)
            return
        }
        windows?.update()
        completionHandler(nil)
    }
}
