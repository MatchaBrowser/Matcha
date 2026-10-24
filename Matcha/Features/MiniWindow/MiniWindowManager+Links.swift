import Foundation

/// Links opened by other apps (task 8.2).
extension MiniWindowManager {
    /// Each link in a mini window, or in a new tab of the Space displayed by the main window (reopened if needed),
    /// which comes to the front.
    func openFromOtherApp(_ urls: [URL], destination: ExternalLinkDestination) {
        switch destination {
        case .miniWindow:
            for url in urls {
                openNew(loading: url, source: .link)
            }
        case .space:
            let space = displayedSpace
            actInMainWindow(on: space)
            let tabs = urls.map { space.tabManager.newTab(url: $0) }
            if let last = tabs.last {
                reveal(last, in: space) { openMainWindow?() }
            }
        }
    }
}
