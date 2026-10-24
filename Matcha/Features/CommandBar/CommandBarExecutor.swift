import AppKit
import OSLog
import SwiftUI

/// Effects of the command bar rows on the window:
/// - address, search, suggestion, history: in the target tab (⌘L, which keeps its place even when pinned or a
///   favorite), otherwise in a new tab of the displayed Space;
/// - open tab: selected in its Space, then that Space is shown (animated) if it was not; from a window of its own tabs,
///   in the main window (`revealInSpace`); a tab of another window of its own tabs: in that window, brought to the
///   front;
/// - actions: new Space (animated), URL copy (like ⇧⌘C), Settings;
/// - Return with no text in new tab mode: an empty tab.
/// The page of the opened or chosen tab then takes the keyboard.
@MainActor
struct CommandBarExecutor {
    let model: CommandBarModel
    let window: NSWindow?
    let openSettings: () -> Void
    /// Shows a tab of a Space in the main window, brought to the front (reopened if needed); nil in a private window.
    var revealInSpace: ((BrowserTab, SpaceSession) -> Void)?
    var pasteboard: NSPasteboard = .general
    /// Animated Space change (tests apply it as is).
    var animate: (() -> Void) -> Void = { change in withMotion(.easeInOut(duration: 0.3), change) }

    private var windowModel: WindowModel {
        model.windowModel
    }

    /// ⏎ or click: closes the bar, gives the keyboard back to the window, runs, then gives the keyboard to the page.
    func submit(_ rowID: CommandRow.ID?) {
        let submission = model.submission(for: rowID)
        guard submission != .ignore else {
            return
        }
        model.dismiss()
        window?.makeFirstResponder(nil)
        if let tab = perform(submission) {
            TabActivation.focusPage(of: tab)
        }
    }

    /// ⎋ and ⌘W: closes the bar and gives the keyboard back to the displayed page.
    func cancel() {
        model.dismiss()
        window?.makeFirstResponder(nil)
        if let tab = windowModel.selectedTab {
            TabActivation.focusPage(of: tab)
        }
    }

    /// Runs; returns the tab whose page should take the keyboard (nil: touch nothing).
    @discardableResult
    func perform(_ submission: CommandBarSubmission) -> BrowserTab? {
        // In this window, even if another one shows the same Space.
        windowModel.activate()
        switch submission {
        case let .run(.open(url), mode):
            return open(url, mode: mode)
        case let .run(.switchToTab(reference), _):
            return switchToTab(reference)
        case let .run(.perform(action), _):
            return run(action)
        case .openEmptyTab:
            log("emptyTab")
            windowModel.tabManager.newTab()
            return nil
        case .ignore:
            return nil
        }
    }

    /// In the target tab (which keeps its place, even when pinned or a favorite), otherwise in a new tab.
    private func open(_ url: URL, mode: CommandBarMode) -> BrowserTab {
        log("open")
        let tabManager = windowModel.tabManager
        if case let .currentTab(id) = mode, let tab = tabManager.tab(withID: id) {
            tab.load(url)
            tabManager.select(tab)
            return tab
        }
        return tabManager.newTab(url: url)
    }

    /// Selects the tab in its Space, then shows that Space if it is not shown.
    private func switchToTab(_ reference: TabReference) -> BrowserTab? {
        if let tabs = windowModel.session.windowTabs(withID: reference.spaceID), let tab = tabs.tabManager.tab(withID: reference.tabID) {
            log("switch")
            tabs.tabManager.select(tab)
            if tabs !== windowModel.windowTabs {
                tabs.bringWindowToFront?()
            }
            return tab
        }
        guard let (space, tab) = windowModel.locate(reference) else {
            Logger.commandBar.notice("Tab not found")
            return windowModel.selectedTab
        }
        log("switch")
        // A window of its own tabs displays no Space: the main window shows the tab.
        if windowModel.windowTabs != nil {
            revealInSpace?(tab, space)
            return tab
        }
        // Selected in this window, which then shows its Space.
        space.tabManager.activate(windowModel.viewer(in: space))
        space.tabManager.select(tab)
        if space !== windowModel.space {
            let windowModel = windowModel
            animate { windowModel.select(space) }
        }
        return tab
    }

    private func run(_ action: CommandActionID) -> BrowserTab? {
        switch action {
        case .newSpace:
            log("newSpace")
            let windowModel = windowModel
            animate { windowModel.newSpace() }
            return nil
        case .copyURL:
            log("copyURL")
            // Same action as ⇧⌘C: copy and “URL Copied” confirmation.
            windowModel.copySelectedTabURL(to: pasteboard)
            return windowModel.selectedTab
        case .settings:
            log("settings")
            openSettings()
            return nil
        }
    }

    /// Kind of the executed row, never its address.
    private func log(_ kind: String) {
        Logger.commandBar.info("Row run: \(kind, privacy: .public)")
    }
}
