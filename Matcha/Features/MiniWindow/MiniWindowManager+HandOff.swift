import AppKit
import OSLog
import SwiftUI

/// Link with the main window and “Open in Space”.
extension MiniWindowManager {
    // MARK: Main window

    /// Space displayed by the main window; closed: the one it was displaying, otherwise the first.
    var displayedSpace: SpaceSession {
        if let space = mainWindow?.windowModel?.space {
            return space
        }
        return session.spaces.first { $0.id == lastMainSpaceID } ?? session.spaces[0]
    }

    /// Space where the page of a mini window of profile `profileID` goes (button, ⇧⌘O, ⌘-click): see `MiniWindowTarget`.
    func defaultTarget(profileID: UUID?) -> SpaceSession {
        let spaces = session.spaces.map { MiniWindowTarget.Space(id: $0.id, profileID: $0.record.profile?.id) }
        let id = MiniWindowTarget.defaultSpaceID(profileID: profileID, displayedSpaceID: displayedSpace.id, spaces: spaces)
        return session.spaces.first { $0.id == id } ?? displayedSpace
    }

    /// A browsing window reports itself when it appears, when its `NSWindow` changes and when it comes to the front:
    /// it becomes the main window. A pending hand-off (window reopened by “Open in Space”) completes there.
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

    /// The tab actions of `space` apply to the main window, even if another window shows that Space: the pages sent
    /// there are selected in it.
    func actInMainWindow(on space: SpaceSession) {
        if let windowModel = mainWindow?.windowModel {
            space.tabManager.activate(windowModel.viewer(in: space))
        }
    }

    /// A browsing window disappears; the main window's displayed Space is remembered for the next mini windows. The
    /// previous active window, if there is one, becomes the main window.
    func unlinkMainWindow(_ windowModel: WindowModel) {
        if mainWindow?.windowModel === windowModel {
            lastMainSpaceID = windowModel.space.id
        }
        removeMainWindow(windowModel)
    }

    // MARK: Hand-off

    /// The page of `controller` moves into the target Space (see `MiniWindowHandOff`), the mini window closes, the
    /// main window displays that Space and the page takes the keyboard. `openMainWindow` reopens the main window if
    /// it is closed.
    func openInSpace(_ controller: MiniWindowController, openMainWindow: () -> Void) {
        // One page to hand off, and only once (double click, repeated ⇧⌘O).
        guard controller.tab.url != nil, windows.contains(where: { $0 === controller }) else {
            return
        }
        let space = defaultTarget(profileID: controller.profileID)
        if space.record.profile?.id == controller.profileID {
            controller.tab.captureInteractionState()
            // Before any rendering of the main window: the web view never has two parents.
            controller.detachForHandOff()
        }
        actInMainWindow(on: space)
        guard let tab = MiniWindowHandOff.move(controller.tab, profileID: controller.profileID, to: space) else {
            return
        }
        controller.close()
        reveal(tab, in: space, openMainWindow: openMainWindow)
        Logger.miniWindow.info("Page opened in a Space")
    }

    /// The main window displays `space` and comes to the front, the page of `tab` takes the keyboard; if closed, it
    /// is reopened by `openMainWindow` and the page shows there as soon as it appears (`linkMainWindow`).
    func reveal(_ tab: BrowserTab, in space: SpaceSession, openMainWindow: () -> Void) {
        if let link = mainWindow, link.isShown, let windowModel = link.windowModel {
            if windowModel.space !== space {
                withMotion(.easeInOut(duration: 0.3)) { windowModel.select(space) }
            }
            if windowModel.viewer.selectedTabID != tab.id {
                windowModel.showTab(withID: tab.id)
            }
            link.bringToFront()
            TabActivation.focusPage(of: tab)
        } else {
            pendingReveal = (space.id, tab)
            openMainWindow()
        }
    }
}
