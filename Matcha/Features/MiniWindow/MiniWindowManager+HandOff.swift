import AppKit
import OSLog
import SwiftUI

/// Lien avec la fenêtre principale et « Ouvrir dans le Space ».
extension MiniWindowManager {
    // MARK: Fenêtre principale

    /// Space affiché par la fenêtre principale ; fermée : celui qu'elle affichait, sinon le premier.
    var displayedSpace: SpaceSession {
        if let space = mainWindow?.windowModel?.space {
            return space
        }
        return session.spaces.first { $0.id == lastMainSpaceID } ?? session.spaces[0]
    }

    /// Space où va la page d'une mini-fenêtre du profil `profileID` (bouton, ⌘O, ⌘-clic) : voir `MiniWindowTarget`.
    func defaultTarget(profileID: UUID?) -> SpaceSession {
        let spaces = session.spaces.map { MiniWindowTarget.Space(id: $0.id, profileID: $0.record.profile?.id) }
        let id = MiniWindowTarget.defaultSpaceID(profileID: profileID, displayedSpaceID: displayedSpace.id, spaces: spaces)
        return session.spaces.first { $0.id == id } ?? displayedSpace
    }

    /// La fenêtre principale se signale à son affichage et quand sa `NSWindow` change ; une remise en attente
    /// (fenêtre rouverte par « Ouvrir dans le Space ») s'y termine.
    func linkMainWindow(_ link: any MainWindowLink) {
        setMainWindow(link)
        guard let pending = pendingReveal, let windowModel = link.windowModel else {
            return
        }
        pendingReveal = nil
        if let space = session.spaces.first(where: { $0.id == pending.spaceID }), windowModel.space !== space {
            windowModel.select(space)
        }
        TabActivation.focusPage(of: pending.tab)
    }

    /// La fenêtre principale disparaît : son Space affiché est retenu pour les prochaines mini-fenêtres.
    func unlinkMainWindow(_ windowModel: WindowModel) {
        guard let link = mainWindow, link.windowModel === windowModel else {
            return
        }
        lastMainSpaceID = windowModel.space.id
        setMainWindow(nil)
    }

    // MARK: Remise

    /// La page de `controller` passe dans le Space visé (voir `MiniWindowHandOff`), la mini-fenêtre se ferme, la
    /// fenêtre principale affiche ce Space et la page prend le clavier. `openMainWindow` rouvre la fenêtre
    /// principale si elle est fermée.
    func openInSpace(_ controller: MiniWindowController, openMainWindow: () -> Void) {
        // Une page à remettre, et une seule fois (double clic, ⌘O répété).
        guard controller.tab.url != nil, windows.contains(where: { $0 === controller }) else {
            return
        }
        let space = defaultTarget(profileID: controller.profileID)
        if space.record.profile?.id == controller.profileID {
            controller.tab.captureInteractionState()
            // Avant tout rendu de la fenêtre principale : la vue web n'a jamais deux parents.
            controller.detachForHandOff()
        }
        guard let tab = MiniWindowHandOff.move(controller.tab, profileID: controller.profileID, to: space) else {
            return
        }
        controller.close()
        reveal(tab, in: space, openMainWindow: openMainWindow)
        Logger.miniWindow.info("Page ouverte dans un Space")
    }

    /// La fenêtre principale affiche `space` et passe au premier plan, la page de `tab` prend le clavier ; fermée,
    /// elle est rouverte par `openMainWindow` et la page s'y montre dès son affichage (`linkMainWindow`).
    func reveal(_ tab: BrowserTab, in space: SpaceSession, openMainWindow: () -> Void) {
        if let link = mainWindow, link.isShown, let windowModel = link.windowModel {
            if windowModel.space !== space {
                withAnimation(.easeInOut(duration: 0.3)) { windowModel.select(space) }
            }
            link.bringToFront()
            TabActivation.focusPage(of: tab)
        } else {
            pendingReveal = (space.id, tab)
            openMainWindow()
        }
    }
}
