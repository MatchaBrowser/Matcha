import Foundation

/// What extensions see of the windows and tabs at a given moment (task 6.3). Pure type: two successive states are
/// compared by `ExtensionEventPlanner`, which derives from them the events to give to the extension controller. Windows
/// and tabs are designated by their identifier.
nonisolated struct ExtensionBrowserState: Equatable, Sendable {
    /// A window: its tabs in order, the active tab (the one in front) and the selected tabs (the panes of the displayed
    /// split, the active tab included).
    struct Window: Equatable, Sendable {
        var id: UUID
        var tabIDs: [UUID]
        var activeTabID: UUID?
        var selectedTabIDs: Set<UUID> = []
    }

    /// Properties of a tab tracked by extensions (`tabs.onUpdated`).
    struct Tab: Equatable, Sendable {
        var title: String?
        var url: URL?
        var isLoading = false
        var isPlayingAudio = false
        var isPinned = false
        var zoomFactor = 1.0
    }

    /// Location of a tab: its window and its index in it.
    struct Location: Equatable, Sendable {
        var windowID: UUID
        var index: Int
    }

    /// Windows, in the order in which they were seen.
    var windows: [Window] = []
    var tabs: [UUID: Tab] = [:]
    /// Active window (the app's key window); nil if no window seen by extensions is.
    var focusedWindowID: UUID?

    func window(withID id: UUID) -> Window? {
        windows.first { $0.id == id }
    }

    /// Location of each tab; a tab present twice keeps the first one.
    func locations() -> [UUID: Location] {
        var result: [UUID: Location] = [:]
        for window in windows {
            for (index, id) in window.tabIDs.enumerated() where result[id] == nil {
                result[id] = Location(windowID: window.id, index: index)
            }
        }
        return result
    }
}

/// An event to give to the extension controller (`WKWebExtensionController.didOpenTab…`).
nonisolated enum ExtensionEvent: Equatable, Sendable {
    /// Window opened; WebKit opens its tabs itself (`didOpenWindow`).
    case openWindow(UUID)
    case openTab(UUID)
    /// Tab moved: from index `fromIndex` of window `oldWindowID` (the same one or another).
    case moveTab(UUID, fromIndex: Int, oldWindowID: UUID)
    case changeTab(UUID, ExtensionTabChanges)
    /// New active tab of its window; WebKit then reads the window's selected tabs again.
    case activateTab(UUID, previousTabID: UUID?)
    case selectTabs([UUID])
    case deselectTabs([UUID])
    case closeTab(UUID, windowIsClosing: Bool)
    case closeWindow(UUID)
    case focusWindow(UUID?)
}
