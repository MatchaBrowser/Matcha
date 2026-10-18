import Foundation

/// Liens ouverts par d'autres apps (tâche 8.2).
extension MiniWindowManager {
    /// Chaque lien dans une mini-fenêtre, ou dans un nouvel onglet du Space affiché par la fenêtre principale (rouverte
    /// au besoin), qui passe au premier plan.
    func openFromOtherApp(_ urls: [URL], destination: ExternalLinkDestination) {
        switch destination {
        case .miniWindow:
            for url in urls {
                openNew(loading: url, source: .link)
            }
        case .space:
            let space = displayedSpace
            let tabs = urls.map { space.tabManager.newTab(url: $0) }
            if let last = tabs.last {
                reveal(last, in: space) { openMainWindow?() }
            }
        }
    }
}
