import AppKit
import OSLog
import SwiftUI
import WebKit

/// Une mini-fenêtre : son panneau, sa page (un `BrowserTab` hors de tout Space, jamais enregistré), le conteneur
/// de sa vue web et sa barre de commande. Créée et suivie par `MiniWindowManager`.
@MainActor
final class MiniWindowController: NSObject, Identifiable {
    let id = UUID()
    let tab: BrowserTab
    /// Profil dont la page utilise les cookies (celui du Space affiché à l'ouverture).
    let profileID: UUID?
    let commandBar: MiniCommandBarModel
    let panel: MiniWindowPanel
    let container = MiniWebViewContainer()
    /// Confirmation « URL copiée » de cette mini-fenêtre (⇧⌘C, ligne « Copier l'URL »).
    let copyConfirmation = CopyConfirmationModel()
    private weak var manager: MiniWindowManager?
    /// La page est partie dans un Space : la fermeture ne doit pas la libérer.
    private(set) var isHandedOff = false

    init(tab: BrowserTab, profileID: UUID?, frame: CGRect, manager: MiniWindowManager) {
        self.tab = tab
        self.profileID = profileID
        self.manager = manager
        commandBar = MiniCommandBarModel(
            tab: tab,
            faviconService: manager.session.faviconService,
            history: manager.session.history.map { ProfileHistory(store: $0, profileID: profileID) },
        )
        panel = MiniWindowPanel(frame: frame)
        super.init()
        panel.delegate = self
        // ⎋ que personne n'a gardé : une mini-fenêtre sans page se ferme ; avec une page, rien (la page reste).
        panel.cancelHandler = { [weak self] in
            if let self, tab.url == nil {
                close()
            }
        }
        let host = NSHostingView(rootView: MiniWindowView(controller: self, manager: manager))
        // La taille vient du panneau (réglée par l'utilisateur), jamais du contenu SwiftUI.
        host.sizingOptions = []
        panel.contentView = host
        showWebView()
    }

    /// Montre la vue web de la page (créée au premier chargement).
    func showWebView() {
        if let webView = tab.webView {
            container.attach(webView)
        }
    }

    // MARK: Barre de commande

    /// ⌘L et clic sur l'adresse ; ⌘T, ⌥⌘N et le menu : saisie neuve.
    func showCommandBar(_ mode: MiniCommandBarMode) {
        commandBar.present(mode, settings: manager?.commandBarSettings() ?? MiniWindowSettings.current())
    }

    /// ⏎ ou clic sur une ligne : la barre se ferme, puis la page charge l'adresse (ou elle est copiée) et prend
    /// le clavier.
    func submit(_ rowID: CommandRow.ID?) {
        let submission = commandBar.submission(for: rowID)
        guard submission != .ignore else {
            return
        }
        commandBar.dismiss()
        panel.makeFirstResponder(nil)
        switch submission {
        case let .load(url):
            Logger.miniWindow.info("Adresse chargée dans une mini-fenêtre")
            tab.load(url)
            showWebView()
        case .copyURL:
            copyURL()
        case .ignore:
            return
        }
        TabActivation.focusPage(of: tab)
    }

    /// ⎋ dans le champ : la barre se ferme ; sans page, la mini-fenêtre aussi (rien ne reste).
    func cancelCommandBar() {
        commandBar.dismiss()
        guard tab.url != nil else {
            close()
            return
        }
        panel.makeFirstResponder(nil)
        TabActivation.focusPage(of: tab)
    }

    /// ⌘W : ferme la barre si elle est ouverte, sinon la mini-fenêtre.
    func closeCommand() {
        if commandBar.isPresented {
            cancelCommandBar()
        } else {
            close()
        }
    }

    /// ⇧⌘C et la ligne « Copier l'URL » : l'adresse de la page, avec la confirmation « URL copiée ».
    func copyURL(to pasteboard: NSPasteboard = .general) {
        guard let url = tab.url else {
            return
        }
        TabLinkCopier.copy(url, to: pasteboard)
        copyConfirmation.show()
        // Jamais l'adresse elle-même.
        Logger.miniWindow.info("Adresse copiée depuis une mini-fenêtre")
    }

    // MARK: Fermeture

    /// « Ouvrir dans le Space » : la vue web quitte le conteneur tout de suite, avant que la fenêtre principale
    /// ne l'affiche ; la fermeture qui suit ne libère pas la page.
    func detachForHandOff() {
        isHandedOff = true
        commandBar.dismiss()
        container.detach()
    }

    /// Toutes les fermetures passent par ici (×, ⌘W, ⇧⌘W, ⎋ sans page, `window.close()`, remise, profil supprimé).
    func close() {
        panel.close()
    }
}

extension MiniWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_: Notification) {
        manager?.keyChanged(self, isKey: true)
    }

    func windowDidResignKey(_: Notification) {
        manager?.keyChanged(self, isKey: false)
    }

    func windowDidEndLiveResize(_: Notification) {
        manager?.rememberSize(panel.frame.size)
    }

    /// Fermeture pour de bon : la page est libérée (son, processus), sauf si elle est partie dans un Space.
    func windowWillClose(_: Notification) {
        commandBar.dismiss()
        copyConfirmation.cancel()
        if !isHandedOff {
            container.detach()
            tab.unload(resettingTo: nil, title: nil)
        }
        manager?.didClose(self)
        panel.delegate = nil
        panel.cancelHandler = nil
        // Garde le contrôleur en vie jusqu'à la fin de la fermeture, puis libère la vue SwiftUI (qui le retient).
        Task { @MainActor in
            self.panel.contentView = nil
        }
    }
}
