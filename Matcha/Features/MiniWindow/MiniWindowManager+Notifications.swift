import AppKit

/// Click on a website's notification (`PageNotificationCenter`): its page comes back to the front, in its mini window,
/// its window of its own tabs or the main window on its Space (reopened if needed). A page that is in none of them
/// (Peek) only brings Matcha to the front, which macOS does.
extension MiniWindowManager: PageNotificationRevealing {
    func reveal(_ page: BrowserTab) {
        if let controller = windows.first(where: { $0.tab === page }) {
            controller.panel.makeKeyAndOrderFront(nil)
        } else if let tabs = session.windowTabs.first(where: { $0.tabManager.tab(withID: page.id) === page }) {
            tabs.tabManager.select(page)
            tabs.bringWindowToFront?()
            TabActivation.focusPage(of: page)
        } else if let space = session.spaces.first(where: { $0.tabManager.tab(withID: page.id) === page }) {
            reveal(page, in: space) { openMainWindow?() }
        }
    }
}
