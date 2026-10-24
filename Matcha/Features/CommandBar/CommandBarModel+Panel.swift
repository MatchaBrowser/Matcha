import Foundation

/// The bar of a browser window as seen by its panel.
extension CommandBarModel: CommandBarPanelModel {
    /// Target tab in “displayed tab” mode.
    var editedTab: BrowserTab? {
        guard case let .currentTab(id) = mode else {
            return nil
        }
        return windowModel.tabManager.tab(withID: id)
    }

    var rowIcons: CommandRowIcons {
        let windowModel = windowModel
        return CommandRowIcons(faviconService: windowModel.session.faviconService) { windowModel.locate($0)?.tab }
    }
}
