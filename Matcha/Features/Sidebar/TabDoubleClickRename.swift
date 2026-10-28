import SwiftUI

/// A double click on a pinned tab or a favorite renames it, if Settings > General allows it (off by default): in its
/// row for a pinned tab's row (`inRow`), otherwise in the window's alert (`TabRenameAlert`). The double click is
/// recognized alongside the click: the first click still selects the tab at once, the second starts the renaming.
/// Option off, the gesture takes no part, and a click is never delayed.
struct TabDoubleClickRename: ViewModifier {
    let tab: BrowserTab
    let tabManager: TabManager
    let inRow: Bool

    @Environment(\.renamesTabsOnDoubleClick) private var isEnabled
    @Environment(WindowModel.self) private var windowModel: WindowModel?

    func body(content: Content) -> some View {
        content.simultaneousGesture(TapGesture(count: 2).onEnded(rename), isEnabled: isEnabled)
    }

    private func rename() {
        guard tabManager.canRename(tab) else {
            return
        }
        if inRow {
            tabManager.renamingTabID = tab.id
        } else {
            windowModel?.showRenameAlert(for: tab)
        }
    }
}

extension EnvironmentValues {
    /// Option “Double-click a pinned tab or a favorite to rename it”, read once by the window for all its rows.
    @Entry var renamesTabsOnDoubleClick = BrowserSettings.renamesTabsOnDoubleClick
}

extension View {
    /// See `TabDoubleClickRename`.
    func renamesOnDoubleClick(_ tab: BrowserTab, tabManager: TabManager, inRow: Bool = false) -> some View {
        modifier(TabDoubleClickRename(tab: tab, tabManager: tabManager, inRow: inRow))
    }
}
