import AppKit
import KeyboardShortcuts
import Observation
import OSLog
import WebKit

/// Les mini-fenêtres de l'app (équivalent de Little Arc) : raccourci global, création, fenêtre active, niveau
/// flottant, et lien avec la fenêtre principale pour « Ouvrir dans le Space » (`+HandOff`). Une seule instance,
/// créée par `MatchaApp` ; les mini-fenêtres ne sont jamais privées, enregistrées ni restaurées.
@MainActor
@Observable
final class MiniWindowManager {
    /// D'où vient une ouverture (journal seulement).
    enum Source: String {
        case shortcut, menu, page, link
    }

    @ObservationIgnored let session: BrowserSession
    /// Où retenir la taille choisie à la souris ; nil avec une base de test (rien n'est retenu).
    @ObservationIgnored let defaults: UserDefaults?
    /// Délégué de navigation des pages des mini-fenêtres (hôte : ce gestionnaire).
    @ObservationIgnored let coordinator = NavigationCoordinator()
    /// Mini-fenêtres ouvertes, de la plus ancienne à la plus récente.
    @ObservationIgnored private(set) var windows: [MiniWindowController] = []
    /// Mini-fenêtre active, suivie pour que les menus se mettent à jour ; l'action relit `keyWindow`.
    private(set) var keyWindowID: MiniWindowController.ID?
    /// Fenêtre de navigation principale (jamais une fenêtre privée) ; le bouton « Ouvrir dans … » la suit.
    private(set) var mainWindow: (any MainWindowLink)?
    /// Space affiché par la fenêtre principale quand elle s'est fermée (au lancement : celui retenu).
    @ObservationIgnored var lastMainSpaceID: UUID?
    /// Page à montrer dès que la fenêtre principale rouvre.
    @ObservationIgnored var pendingReveal: (spaceID: UUID, tab: BrowserTab)?

    /// Configuration WebKit d'une nouvelle page, pour le magasin de son profil (remplacée dans les tests).
    @ObservationIgnored var makeConfiguration: @MainActor (WKWebsiteDataStore) -> WKWebViewConfiguration =
        WebConfigurationFactory.makeConfiguration(websiteDataStore:)
    /// Montre un panneau et active l'app (remplacé dans les tests : aucun panneau à l'écran).
    @ObservationIgnored var present: @MainActor (MiniWindowPanel) -> Void = MiniWindowManager.presentOnScreen
    /// Zone utile de l'écran où ouvrir une mini-fenêtre : celui du pointeur.
    @ObservationIgnored var visibleScreenFrame: @MainActor () -> CGRect? = MiniWindowManager.screenUnderPointer
    /// Moteur et suggestions, lus à chaque ouverture de la barre.
    @ObservationIgnored var commandBarSettings: @MainActor () -> CommandBarSettings = { MiniWindowSettings.current() }

    @ObservationIgnored private var shortcutTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    /// Sans effet de bord : `start()` branche le raccourci global et l'activation de l'app.
    init(session: BrowserSession, defaults: UserDefaults?) {
        self.session = session
        self.defaults = defaults
        lastMainSpaceID = defaults?.string(forKey: WindowModel.currentSpaceKey).flatMap(UUID.init(uuidString:))
        coordinator.tabHost = self
    }

    /// Écoute le raccourci global (même quand Matcha n'est pas au premier plan) et l'activation de l'app.
    /// Sans effet au second appel ; jamais appelé dans l'app hôte des tests unitaires.
    func start() {
        guard shortcutTask == nil else {
            return
        }
        shortcutTask = Task { [weak self] in
            for await _ in KeyboardShortcuts.events(.keyDown, for: .openMiniWindow) {
                guard let self else {
                    return
                }
                // Pendant une alerte modale (« Quitter Matcha ? »), aucune fenêtre ne prendrait le clavier.
                guard NSApp.modalWindow == nil else {
                    Logger.miniWindow.notice("Raccourci de la mini-fenêtre ignoré pendant une alerte")
                    continue
                }
                openNew(source: .shortcut)
            }
        }
        observe(NSApplication.didResignActiveNotification) { MiniWindowLevels.lower($0.windows.map(\.panel)) }
        observe(NSApplication.didBecomeActiveNotification) { MiniWindowLevels.raise($0.windows.map(\.panel)) }
    }

    // MARK: Fenêtres

    /// Mini-fenêtre active, lue au moment de l'action.
    var keyWindow: MiniWindowController? {
        windows.first { $0.panel.isKeyWindow }
    }

    func window(for tab: BrowserTab) -> MiniWindowController? {
        windows.first { $0.tab === tab }
    }

    func window(for webView: WKWebView) -> MiniWindowController? {
        windows.first { $0.tab.webView === webView }
    }

    // MARK: Ouverture

    /// ⌥⌘N, menu Fichier : une mini-fenêtre vide, barre ouverte, dans le profil du Space affiché (jamais privée).
    /// `url` (tâche 8.2 : liens venus d'autres apps) : la page se charge, la barre reste fermée.
    @discardableResult
    func openNew(loading url: URL? = nil, source: Source) -> MiniWindowController {
        let profile = displayedSpace.record.profile
        let tab = BrowserTab(configuration: makeConfiguration(session.dataStore(for: profile)))
        let controller = show(tab, profileID: profile?.id)
        if let url {
            tab.load(url)
            controller.showWebView()
        } else {
            controller.showCommandBar(.newSearch)
        }
        Logger.miniWindow.info("Mini-fenêtre ouverte (\(source.rawValue, privacy: .public))")
        return controller
    }

    /// Crée le panneau de `tab`, décalé de la dernière mini-fenêtre ouverte, et le montre au premier plan.
    @discardableResult
    func show(_ tab: BrowserTab, profileID: UUID?) -> MiniWindowController {
        tab.delegate = coordinator
        let size = MiniWindowPlacement.storedSize(defaults?.string(forKey: MiniWindowPlacement.sizeKey)) ?? MiniWindowPlacement.defaultSize
        let visible = visibleScreenFrame() ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = MiniWindowPlacement.frame(size: size, in: visible, after: windows.last?.panel.frame)
        let controller = MiniWindowController(tab: tab, profileID: profileID, frame: frame, manager: self)
        windows.append(controller)
        present(controller.panel)
        return controller
    }

    // MARK: Suivi

    func keyChanged(_ controller: MiniWindowController, isKey: Bool) {
        if isKey {
            keyWindowID = controller.id
        } else if keyWindowID == controller.id {
            keyWindowID = nil
        }
    }

    func didClose(_ controller: MiniWindowController) {
        windows.removeAll { $0 === controller }
        if keyWindowID == controller.id {
            keyWindowID = nil
        }
    }

    /// Taille choisie à la souris : la prochaine mini-fenêtre la reprend (jamais avec une base de test).
    func rememberSize(_ size: CGSize) {
        defaults?.set(NSStringFromSize(size), forKey: MiniWindowPlacement.sizeKey)
    }

    /// Primitive de `+HandOff` : fenêtre principale signalée ou disparue.
    func setMainWindow(_ link: (any MainWindowLink)?) {
        mainWindow = link
    }

    /// Profil supprimé : ses mini-fenêtres se ferment avant que ses données ne le soient.
    func closeWindows(ofProfile profileID: UUID) {
        for controller in windows where controller.profileID == profileID {
            controller.close()
        }
    }

    // MARK: Écran

    static func presentOnScreen(_ panel: MiniWindowPanel) {
        panel.makeKeyAndOrderFront(nil)
        // Raccourci pressé dans une autre app : l'activation coopérative (`NSApp.activate()`) y est refusée et
        // la mini-fenêtre n'aurait pas le clavier. `activate(ignoringOtherApps:)` est marquée
        // `API_TO_BE_DEPRECATED` dans le SDK, sans avertissement à la compilation.
        NSApp.activate(ignoringOtherApps: true)
    }

    static func screenUnderPointer() -> CGRect? {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        return screen?.visibleFrame
    }

    private func observe(_ name: Notification.Name, _ handle: @escaping @MainActor (MiniWindowManager) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self {
                    handle(self)
                }
            }
        })
    }
}
