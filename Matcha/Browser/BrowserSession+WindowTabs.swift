import Foundation
import OSLog

/// Windows without a Space (`WindowTabs`): their tabs are made with the settings of the Space they come from, and go
/// back to it when the app quits.
extension BrowserSession {
    /// New empty tab list for a window, with the profile, history and settings of `space`.
    func makeWindowTabs(from space: SpaceSession) -> WindowTabs {
        let source = space.tabManager
        let manager = TabManager(websiteDataStore: source.websiteDataStore, services: services, downloadScope: downloadScope)
        manager.sitePermissions = source.sitePermissions
        manager.siteZooms = source.siteZooms
        manager.history = source.history
        manager.lifecycle = tabLifecycle
        manager.popupWindows = popupWindows
        manager.contentBlocking = contentBlocking
        let tabs = WindowTabs(tabManager: manager, space: space)
        windowTabs.append(tabs)
        return tabs
    }

    func windowTabs(withID id: UUID?) -> WindowTabs? {
        windowTabs.first { $0.id == id }
    }

    /// The window no longer has its own tabs (moved to a Space, closed).
    func removeWindowTabs(_ tabs: WindowTabs) {
        windowTabs.removeAll { $0 === tabs }
    }

    /// App quitting: the tabs of each window without a Space go back to the top of the today tabs of their Space
    /// (otherwise the first Space of their profile), to be saved with it.
    func returnWindowTabs() {
        for tabs in windowTabs {
            let space = tabs.space.flatMap { origin in spaces.first { $0 === origin } }
                ?? spaces.first { $0.openedProfileID == tabs.space?.openedProfileID }
            guard let space else {
                continue
            }
            let count = tabs.tabManager.todayTabs.count
            tabs.move(to: space)
            Logger.browser.info("Window tabs returned to their Space: \(count, privacy: .public)")
        }
        windowTabs = []
    }
}
