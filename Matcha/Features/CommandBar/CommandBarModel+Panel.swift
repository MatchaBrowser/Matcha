import Foundation

/// La barre d'une fenêtre de navigation vue par son panneau.
extension CommandBarModel: CommandBarPanelModel {
    /// Onglet visé en mode « onglet affiché ».
    var editedTab: BrowserTab? {
        guard case let .currentTab(id) = mode else {
            return nil
        }
        return windowModel.space.tabManager.tab(withID: id)
    }

    var rowIcons: CommandRowIcons {
        let windowModel = windowModel
        return CommandRowIcons(faviconService: windowModel.session.faviconService) { windowModel.locate($0)?.tab }
    }
}
