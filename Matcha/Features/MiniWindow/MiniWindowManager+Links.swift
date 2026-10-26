import Foundation

/// Links opened by other apps (task 8.2).
extension MiniWindowManager {
    /// Each link in a mini window, or in a new tab of the Space displayed by the main window (reopened if needed),
    /// which comes to the front. `isChosenByUser`: files chosen with ⌘O from a mini window, which read their folder; a
    /// file received from another app reads only itself, unless the setting says otherwise (review WB11).
    func openFromOtherApp(_ urls: [URL], destination: ExternalLinkDestination, isChosenByUser: Bool = false) {
        let readsFolder = defaults.map { BrowserSettings.readsFolderOfFilesFromOtherApps(in: $0) }
            ?? BrowserSettings.filesFromOtherAppsReadFolder
        let isFromAnotherApp = !isChosenByUser && !readsFolder
        switch destination {
        case .miniWindow:
            for url in urls {
                openNew(loading: url, source: .link, isFromAnotherApp: isFromAnotherApp)
            }
        case .space:
            let space = displayedSpace
            actInMainWindow(on: space)
            let tabs = urls.map { space.tabManager.newTab(url: $0, isFromAnotherApp: isFromAnotherApp) }
            if let last = tabs.last {
                reveal(last, in: space) { openMainWindow?() }
            }
        }
    }
}
