import Foundation

/// Names of pinned tabs and favorites (`BrowserTab.customTitle`): shown in place of the page's title, saved and synced
/// (`SYNC.md` § 2.1). A today tab has none.
extension TabManager {
    /// Only a pinned tab or a favorite can be renamed.
    func canRename(_ tab: BrowserTab) -> Bool {
        guard let place = layout.place(of: tab.id) else {
            return false
        }
        return place != .today
    }

    /// Gives `tab` the name `name`, and ends the editing of its name. The title already shown (field left as it was)
    /// changes nothing; an empty name gives the page's title back.
    func renameTab(_ tab: BrowserTab, to name: String) {
        endRenaming(tab)
        guard canRename(tab) else {
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            tab.customTitle = nil
        } else if trimmed != tab.displayTitle {
            tab.customTitle = trimmed
        }
    }

    /// Ends the editing of the tab's name in its row, without changing it (Escape, row gone).
    func endRenaming(_ tab: BrowserTab) {
        if renamingTabID == tab.id {
            renamingTabID = nil
        }
    }
}
