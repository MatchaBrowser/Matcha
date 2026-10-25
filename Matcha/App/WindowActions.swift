import Foundation

/// Actions that the active window offers to menu commands. Two values that differ only by their closures are equal
/// (`==`): a new drawing of the window gives new closures, and without that the menus were recomputed each time
/// (review IU1). The closures read the window's current state; what they keep is in `target`.
struct WindowActions: Equatable {
    /// What the closures act on: the window's model, its `NSWindow`, the homepage of `goHome`.
    struct Target: Equatable {
        let model: ObjectIdentifier
        let window: ObjectIdentifier?
        let homeURL: URL?
    }

    let target: Target
    /// Opens the command bar (new tab), or a tab on the homepage if the settings ask for it.
    let newTab: () -> Void
    /// Opens the command bar on the address of the displayed tab (⌘L).
    let editAddress: () -> Void
    /// Command bar open: ⌘W closes it instead of closing the tab.
    let isCommandBarPresented: Bool
    /// Closes the command bar and gives keyboard focus back to the page.
    let closeCommandBar: () -> Void
    /// Hides or shows the sidebar.
    let toggleSidebar: () -> Void
    let isSidebarVisible: Bool
    /// Opens or closes the downloads panel (⌥⌘L); if the sidebar is hidden, it is shown first.
    let toggleDownloads: () -> Void
    /// Downloads panel visible (open, in a shown sidebar): the menu offers to hide it.
    let isDownloadsPanelShown: Bool
    /// Copies the address of the displayed tab and confirms “URL Copied” (⇧⌘C), like the command bar
    /// action; nil if the displayed tab has no address.
    let copyURL: (() -> Void)?
    /// Loads the homepage; nil without a homepage set.
    let goHome: (() -> Void)?
    /// Displayed Space, which a new window shows; nil in a private window (its Spaces are its own).
    let spaceID: UUID?
    /// Names of the Spaces, in sidebar order.
    let spaceNames: [String]
    let currentSpaceIndex: Int
    let selectSpace: (Int) -> Void
    let newSpace: () -> Void
    /// Shows a tab of the window like a click on its row (⌘1 to ⌘9, ⌃⇥): the command bar and the peek close, the
    /// page takes keyboard focus.
    let showTab: (BrowserTab) -> Void
    /// Private window: “Show All History” (⌘Y) is disabled there, it has no history.
    let isPrivate: Bool
    /// File > Import From > Arc… (task 7.1); nil in a private window.
    let importFromArc: (() -> Void)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.target == rhs.target && lhs.state == rhs.state
    }

    /// What the menus show.
    private var state: [AnyHashable] {
        [
            isCommandBarPresented, isSidebarVisible, isDownloadsPanelShown, copyURL != nil, goHome != nil, spaceID,
            spaceNames, currentSpaceIndex, isPrivate, importFromArc != nil,
        ]
    }
}
