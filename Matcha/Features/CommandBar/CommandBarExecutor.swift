import AppKit
import OSLog
import SwiftUI

/// Effets des lignes de la barre de commande sur la fenêtre :
/// - adresse, recherche, suggestion, historique : dans l'onglet visé (⌘L, qui garde sa place même
///   épinglé ou favori), sinon dans un nouvel onglet du Space affiché ;
/// - onglet ouvert : sélection dans son Space, puis ce Space s'affiche (animé) s'il ne l'était pas ;
/// - actions : nouveau Space (animé), copie de l'URL (comme ⇧⌘C), Réglages ;
/// - Entrée sans texte en mode nouvel onglet : un onglet vide.
/// La page de l'onglet ouvert ou choisi prend ensuite le clavier.
@MainActor
struct CommandBarExecutor {
    let model: CommandBarModel
    let window: NSWindow?
    let openSettings: () -> Void
    var pasteboard: NSPasteboard = .general
    /// Changement de Space animé (les tests l'appliquent tel quel).
    var animate: (() -> Void) -> Void = { change in withAnimation(.easeInOut(duration: 0.3), change) }

    private var windowModel: WindowModel {
        model.windowModel
    }

    /// ⏎ ou clic : ferme la barre, rend le clavier à la fenêtre, exécute, puis donne le clavier à la page.
    func submit(_ rowID: CommandRow.ID?) {
        let submission = model.submission(for: rowID)
        guard submission != .ignore else {
            return
        }
        model.dismiss()
        window?.makeFirstResponder(nil)
        if let tab = perform(submission) {
            TabActivation.focusPage(of: tab)
        }
    }

    /// ⎋ et ⌘W : ferme la barre et rend le clavier à la page affichée.
    func cancel() {
        model.dismiss()
        window?.makeFirstResponder(nil)
        if let tab = windowModel.space.tabManager.selectedTab {
            TabActivation.focusPage(of: tab)
        }
    }

    /// Exécute ; renvoie l'onglet dont la page doit prendre le clavier (nil : ne rien toucher).
    @discardableResult
    func perform(_ submission: CommandBarSubmission) -> BrowserTab? {
        switch submission {
        case let .run(.open(url), mode):
            return open(url, mode: mode)
        case let .run(.switchToTab(reference), _):
            return switchToTab(reference)
        case let .run(.perform(action), _):
            return run(action)
        case .openEmptyTab:
            log("emptyTab")
            windowModel.space.tabManager.newTab()
            return nil
        case .ignore:
            return nil
        }
    }

    /// Dans l'onglet visé (qui garde sa place, même épinglé ou favori), sinon dans un nouvel onglet.
    private func open(_ url: URL, mode: CommandBarMode) -> BrowserTab {
        log("open")
        let tabManager = windowModel.space.tabManager
        if case let .currentTab(id) = mode, let tab = tabManager.tab(withID: id) {
            tab.load(url)
            tabManager.select(tab)
            return tab
        }
        return tabManager.newTab(url: url)
    }

    /// Sélectionne l'onglet dans son Space, puis affiche ce Space s'il ne l'est pas.
    private func switchToTab(_ reference: TabReference) -> BrowserTab? {
        guard let (space, tab) = windowModel.locate(reference) else {
            Logger.commandBar.notice("Onglet introuvable")
            return windowModel.space.tabManager.selectedTab
        }
        log("switch")
        space.tabManager.select(tab)
        if space !== windowModel.space {
            let windowModel = windowModel
            animate { windowModel.select(space) }
        }
        return tab
    }

    private func run(_ action: CommandActionID) -> BrowserTab? {
        let tabManager = windowModel.space.tabManager
        switch action {
        case .newSpace:
            log("newSpace")
            let windowModel = windowModel
            animate { windowModel.newSpace() }
            return nil
        case .copyURL:
            log("copyURL")
            // Même action que ⇧⌘C : copie et confirmation « URL copiée ».
            windowModel.copySelectedTabURL(to: pasteboard)
            return tabManager.selectedTab
        case .settings:
            log("settings")
            openSettings()
            return nil
        }
    }

    /// Nature de la ligne exécutée, jamais son adresse.
    private func log(_ kind: String) {
        Logger.commandBar.info("Ligne exécutée : \(kind, privacy: .public)")
    }
}
