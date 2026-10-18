import AppKit
import SwiftUI
import WebKit

/// Une fenêtre de connexion (tâche 5.8) : sa fenêtre, sa page (un `BrowserTab` hors de tout Space, jamais
/// enregistré), le conteneur de sa vue web et la page qui l'a ouverte. Créée et suivie par `PopupWindowManager`.
///
/// Elle est fenêtre enfant de la fenêtre d'origine : elle reste au-dessus d'elle (un clic sur la fenêtre du navigateur
/// ne la cache pas), la suit quand on la déplace et prend son niveau (au-dessus des autres fenêtres avec une
/// mini-fenêtre). AppKit retire les enfants de l'écran avec leur parent : quand la fenêtre d'origine se ferme, la
/// fenêtre de connexion s'en détache et reste ouverte.
@MainActor
final class PopupWindowController: NSObject, Identifiable {
    let id = UUID()
    let tab: BrowserTab
    let opener: PopupOpener
    let window: PopupWindow
    let container = MiniWebViewContainer()
    private weak var manager: PopupWindowManager?
    private var parentObserver: (any NSObjectProtocol)?

    init(tab: BrowserTab, opener: PopupOpener, frame: CGRect, isPrivate: Bool, manager: PopupWindowManager) {
        self.tab = tab
        self.opener = opener
        self.manager = manager
        window = PopupWindow(frame: frame)
        super.init()
        window.delegate = self
        // Fenêtre privée : sombre, comme elle.
        if isPrivate {
            window.appearance = NSAppearance(named: .darkAqua)
        }
        let host = NSHostingView(rootView: PopupWindowView(controller: self))
        // La taille vient de la fenêtre (demandée par la page, puis réglée par l'utilisateur), jamais du contenu.
        host.sizingOptions = []
        window.contentView = host
        if let webView = tab.webView {
            container.attach(webView)
        }
    }

    /// Place la fenêtre au-dessus de `parent`, la fenêtre d'origine, tant que celle-ci est ouverte.
    func attach(to parent: NSWindow) {
        detachFromParent()
        parent.addChildWindow(window, ordered: .above)
        // Sans file : appelé pendant la fermeture, avant qu'AppKit ne retire les fenêtres enfants de l'écran.
        parentObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: parent,
            queue: nil,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.detachFromParent() }
        }
    }

    /// Plus de fenêtre parente : la fenêtre reste où elle est, au niveau normal (un enfant garde sinon le niveau
    /// de son ancien parent, vérifié).
    func detachFromParent() {
        if let parentObserver {
            NotificationCenter.default.removeObserver(parentObserver)
            self.parentObserver = nil
        }
        if let parent = window.parent {
            parent.removeChildWindow(window)
            window.level = .normal
        }
    }

    /// Fermeture par l'app : `window.close()` de la page, fenêtre privée ou profil fermés, fenêtre qui ne fait que
    /// télécharger. Le bouton, ⌘W et ⇧⌘W ferment la fenêtre directement ; tout finit dans `windowWillClose`.
    func close() {
        window.close()
    }
}

extension PopupWindowController: NSWindowDelegate {
    /// Fermeture pour de bon : la page est libérée (son, processus, demandes de permission refusées).
    func windowWillClose(_: Notification) {
        detachFromParent()
        container.detach()
        tab.unload(resettingTo: nil, title: nil)
        manager?.didClose(self)
        window.delegate = nil
        // Garde le contrôleur en vie jusqu'à la fin de la fermeture, puis libère la vue SwiftUI (qui le retient).
        Task { @MainActor in
            self.window.contentView = nil
        }
    }
}
