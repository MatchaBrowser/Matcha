import SwiftUI

/// Renaming of a tab that has no room for a field (favorite tile, pane of a split, icon of the column): an alert
/// attached to the window, like `SiteDataClearConfirmation`, since the floating sidebar that holds the tab may go away.
/// The field starts with the title shown; emptied, it shows the page's title, which it gives back (`TabManager+Names`).
struct TabRenameAlert: ViewModifier {
    let model: WindowModel

    func body(content: Content) -> some View {
        content.alert(
            "Rename Tab",
            isPresented: Binding { model.renamedTab != nil } set: {
                if !$0 {
                    model.renamedTab = nil
                }
            },
            presenting: model.renamedTab,
        ) { tab in
            TextField(
                "Name",
                text: Binding { model.renamedTabName } set: { model.renamedTabName = $0 },
                prompt: Text(verbatim: tab.pageTitle),
            )
            Button("Rename") { model.tabManager.renameTab(tab, to: model.renamedTabName) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

extension WindowModel {
    /// Opens the alert that renames `tab`, its field starting with the title shown (context menu, double click).
    func showRenameAlert(for tab: BrowserTab) {
        renamedTabName = tab.displayTitle
        renamedTab = tab
    }
}
