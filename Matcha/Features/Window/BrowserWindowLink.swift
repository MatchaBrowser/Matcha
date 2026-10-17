import AppKit

/// Ce que la fenêtre principale offre aux mini-fenêtres (une fausse version dans les tests).
@MainActor
protocol MainWindowLink: AnyObject {
    /// Space affiché ; nil si la fenêtre a disparu.
    var windowModel: WindowModel? { get }
    /// La fenêtre est à l'écran ou dans le Dock.
    var isShown: Bool { get }
    /// Ferme sa barre de commande, la met au premier plan (en la sortant du Dock) et libère son clavier.
    func bringToFront()
}

/// Lien réel, tenu par `MiniWindowManager` ; il ne retient ni la fenêtre ni son état.
@MainActor
final class BrowserWindowLink: MainWindowLink {
    private(set) weak var windowModel: WindowModel?
    private weak var window: NSWindow?
    private let dismissCommandBar: @MainActor () -> Void

    init(windowModel: WindowModel, window: NSWindow?, dismissCommandBar: @escaping @MainActor () -> Void) {
        self.windowModel = windowModel
        self.window = window
        self.dismissCommandBar = dismissCommandBar
    }

    var isShown: Bool {
        guard let window else {
            return false
        }
        return window.isVisible || window.isMiniaturized
    }

    func bringToFront() {
        dismissCommandBar()
        guard let window else {
            return
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
    }
}
