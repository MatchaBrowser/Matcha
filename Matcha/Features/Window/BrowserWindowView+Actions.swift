import SwiftUI

/// What the browser window does for its menus, its command bar and its buttons (audit C3: the view keeps its layout,
/// the actions are here).
extension BrowserWindowView {
    /// Settings read each time the command bar opens, and followed while it is open.
    var commandBarSettings: CommandBarSettings {
        CommandBarSettings(
            searchEngine: searchEngine,
            newTabPage: newTabPage,
            homePage: homePage,
            showsSearchSuggestions: showsSearchSuggestions,
        )
    }

    var commandBarExecutor: CommandBarExecutor {
        CommandBarExecutor(model: commandBar, window: window, openSettings: { openSettings() })
    }

    var windowActions: WindowActions {
        WindowActions(
            newTab: openCommandBarForNewTab,
            editAddress: editAddress,
            isCommandBarPresented: commandBar.isPresented,
            closeCommandBar: commandBarExecutor.cancel,
            toggleSidebar: toggleSidebar,
            isSidebarVisible: isSidebarVisible,
            toggleDownloads: toggleDownloads,
            isDownloadsPanelShown: isDownloadsPanelShown,
            // `hasURL` and not `url`: the window is not recomputed on each address change.
            copyURL: tabManager.frontTab?.hasURL == true ? { model.copySelectedTabURL() } : nil,
            goHome: homeURL.map { url in { goHome(to: url) } },
            spaceNames: session.spaces.map(\.record.name),
            currentSpaceIndex: model.spaceIndex,
            selectSpace: { index in withMotion(.easeInOut(duration: 0.3)) { model.selectSpace(at: index) } },
            newSpace: { withMotion(.easeInOut(duration: 0.3)) { model.newSpace() } },
            showTab: showTab,
            isPrivate: session.isPrivate,
            importFromArc: session.isPrivate ? nil : { model.arcImport.chooseFile(in: window) },
        )
    }

    /// ⌘1 to ⌘9, ⌃⇥ and ⌃⇧⇥: like a click in the sidebar, which closes the command bar and the peek (even on the
    /// tab already displayed).
    func showTab(_ tab: BrowserTab) {
        commandBar.dismiss()
        tabManager.closePeek()
        TabActivation.activate(tab, in: tabManager)
    }

    /// ⌘T and “New Tab”: the command bar, or a tab on the home page.
    func openCommandBarForNewTab() {
        // A single floating layer: the command bar closes the peek.
        tabManager.closePeek()
        commandBar.newTab(commandBarSettings)
    }

    /// ⌘L and the address pill: the command bar on the address of the displayed tab.
    func editAddress() {
        // A single floating layer: the command bar closes the peek.
        tabManager.closePeek()
        commandBar.editCurrentTab(commandBarSettings)
    }

    func toggleSidebar() {
        withMotion(.easeInOut(duration: 0.2)) {
            isSidebarVisible.toggle()
            isFloatingSidebarHovered = false
        }
    }

    /// ⌥⌘L: hides the downloads panel if it is visible; otherwise shows the hidden sidebar, then opens it.
    func toggleDownloads() {
        let show = !isDownloadsPanelShown
        withMotion(.easeInOut(duration: 0.2)) {
            if show, !isSidebarVisible {
                isSidebarVisible = true
                isFloatingSidebarHovered = false
            }
            model.isDownloadsPresented = show
        }
    }

    /// Action of the Home button, if it is displayed and a home page is set.
    var homeButtonAction: (() -> Void)? {
        showsHomeButton ? windowActions.goHome : nil
    }

    var homeURL: URL? {
        BrowserSettings.homeURL(from: homePage, searchEngine: searchEngine)
    }

    /// Loads the home page in the selected tab, or in a new tab if there is none.
    func goHome(to url: URL) {
        tabManager.closePeek()
        if let tab = tabManager.selectedTab {
            tab.load(url)
        } else {
            tabManager.newTab(url: url)
        }
    }
}
