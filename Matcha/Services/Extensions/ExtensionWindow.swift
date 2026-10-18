import AppKit
import WebKit

/// Une fenêtre telle que la voient les extensions (tâche 6.3) : adaptateur `WKWebExtensionWindow` d'une fenêtre de
/// navigation, d'une mini-fenêtre ou d'une fenêtre de connexion, désignée par son identifiant et relue dans
/// `ExtensionWindows`. Un objet par fenêtre, toujours le même tant qu'elle est ouverte. Son type et le fait qu'elle soit
/// privée ne changent pas (WebKit les garde dès la première lecture). Non pris en charge : changer sa taille ou son
/// état (réduite, plein écran).
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

    /// Met la fenêtre au premier plan (sortie du Dock comprise) et active l'app.
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

    /// Une mini-fenêtre ou une fenêtre de connexion se ferme ; une fenêtre de navigation, non : elle porte tous les
    /// Spaces (et une fenêtre privée, toute sa navigation).
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
