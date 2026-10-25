import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

/// State of a window: the displayed Space and the tab selected in each Space (`WindowModel+Viewers`), the edge from
/// which the chosen Space arrives (animation), the “URL Copied” confirmation, the downloads list, the site settings
/// panel and the folder customization panel.
@MainActor
@Observable
final class WindowModel {
    static let currentSpaceKey = "currentSpaceID"

    let session: BrowserSession
    private(set) var currentSpaceID: UUID?
    private(set) var transitionEdge = Edge.trailing
    /// Confirmation shown for each address copied from this window.
    let copyConfirmation = CopyConfirmationModel()
    /// Downloads panel open (task 5.1), through the sidebar footer button or ⌥⌘L; only the user opens and closes it.
    /// With the sidebar hidden, it reappears with the floating sidebar.
    var isDownloadsPresented = false
    /// Site settings panel open (task 5.2), for the displayed tab; only the user opens and closes it.
    var isSiteSettingsPresented = false
    /// Deletion of a site's data awaiting confirmation (window alert).
    var siteDataClearRequest: SiteDataClearRequest?
    /// Pinned folder whose customization panel is open, under its row: only one per window. Only the user opens and
    /// closes it (folder menu, ×, Escape); it is visible only in the folder's Space.
    var customizedFolderID: UUID?
    /// Space whose editor (popover of its icon, at the bottom of the sidebar) is open. Held here and not by the view:
    /// changing Space recreates the sidebar (`.id` of the Space), which would lose its state before opening the
    /// popover.
    var editedSpaceID: UUID?
    /// Space being renamed, or whose deletion awaits confirmation (alerts of the sidebar footer): held here so that the
    /// floating sidebar stays shown while they are open (review ON19).
    var renamedSpace: SpaceSession?
    var deletedSpace: SpaceSession?
    /// Import from Arc started from this window (task 7.1).
    let arcImport = ArcImportModel()
    /// Where to remember the last displayed Space, shown by the next new window; nil to remember nothing (tests).
    @ObservationIgnored private let defaults: UserDefaults?
    /// This window's viewer of each Space it has shown: its selected tab there.
    @ObservationIgnored var viewers: [UUID: TabViewer] = [:]
    /// Between appearing and closing: the viewer of the displayed Space is on screen.
    @ObservationIgnored var isOpen = false
    /// Closed: its viewers are released, it no longer takes any.
    @ObservationIgnored var isClosed = false
    /// Makes the window's viewers active as soon as it becomes the key window, before the click that made it so.
    @ObservationIgnored var keyObserver: (any NSObjectProtocol)?
    /// The window's own tabs, outside any Space (a tab dragged out of the sidebar, `WindowModel+WindowTabs`): the
    /// sidebar shows only them. The displayed Space is then the one they came from (theme, profile).
    private(set) var windowTabs: WindowTabs?

    /// `spaceID`: the Space the window shows (restored window, new window); otherwise the last displayed one.
    /// `windowTabs`: the window's own tabs (detached tab).
    init(session: BrowserSession, defaults: UserDefaults?, spaceID: UUID? = nil, windowTabs: WindowTabs? = nil) {
        self.session = session
        self.defaults = defaults
        self.windowTabs = windowTabs
        currentSpaceID = spaceID ?? defaults?.string(forKey: Self.currentSpaceKey).flatMap(UUID.init(uuidString:))
    }

    isolated deinit {
        keyObserver.map(NotificationCenter.default.removeObserver)
    }

    /// Displayed Space: the chosen one, otherwise the first.
    var space: SpaceSession {
        session.spaces.first { $0.id == currentSpaceID } ?? session.spaces[0]
    }

    var spaceIndex: Int {
        session.spaces.firstIndex { $0 === space } ?? 0
    }

    /// Tab of `reference` and its Space, if they still exist.
    func locate(_ reference: TabReference) -> (space: SpaceSession, tab: BrowserTab)? {
        guard let space = session.spaces.first(where: { $0.id == reference.spaceID }),
              let tab = space.tabManager.tab(withID: reference.tabID)
        else {
            return nil
        }
        return (space, tab)
    }

    /// Shows `target`, which takes back and now holds the favorites of its profile; its tab actions apply to this
    /// window.
    func select(_ target: SpaceSession) {
        let current = space
        // A window of its own tabs shows no Space (“Move to…” gives them to one).
        guard windowTabs == nil, target !== current, let targetIndex = session.spaces.firstIndex(where: { $0 === target }) else {
            return
        }
        // The tabs displayed here (the whole split) leave the screen: they remember their navigation state; the peek
        // shown here closes.
        let leaving = viewer(in: current)
        current.tabManager.displayedTabs(in: leaving).forEach { $0.captureInteractionState() }
        closePeek()
        // It takes back the favorites of its profile, held until then by another Space.
        session.showFavorites(in: target)
        transitionEdge = targetIndex > spaceIndex ? .trailing : .leading
        // A Space's popover does not survive a Space change (except `editSpace`, which reopens it).
        editedSpaceID = nil
        currentSpaceID = target.id
        defaults?.set(target.id.uuidString, forKey: Self.currentSpaceKey)
        let viewer = viewer(in: target)
        target.tabManager.activate(viewer)
        if isOpen {
            current.tabManager.setOnScreen(leaving, false)
            target.tabManager.setOnScreen(viewer, true)
        }
        target.tabManager.loadSelectedTab()
    }

    func selectSpace(at index: Int) {
        guard session.spaces.indices.contains(index) else {
            return
        }
        select(session.spaces[index])
    }

    /// “Change Icon…” and “Edit Theme…” in a Space's menu: shows it and opens its editor.
    func editSpace(_ target: SpaceSession) {
        select(target)
        editedSpaceID = target.id
    }

    /// Neighboring Space (two-finger swipe), without wrapping.
    func selectAdjacentSpace(_ direction: SpaceSwipeTracker.Direction) {
        selectSpace(at: spaceIndex + (direction == .next ? 1 : -1))
    }

    /// Sends a tab of the window (displayed Space, or the window's own tabs) to `target`. Same profile: the tab keeps
    /// its page and its history. Other profile: it is recreated from its address, with the cookies of that profile.
    func move(_ tab: BrowserTab, to target: SpaceSession) {
        let source = tabManager
        guard target.tabManager !== source else {
            return
        }
        if target.record.profile?.id == space.record.profile?.id {
            if let detached = source.detach(tab) {
                target.tabManager.attach(detached)
            }
        } else {
            let url = tab.url
            source.delete(tab)
            target.tabManager.newTab(url: url, select: false)
        }
    }

    /// Creates a Space in the profile of the displayed Space and shows it.
    func newSpace() {
        select(session.addSpace(inProfileOf: space))
    }

    /// Deletes `target`; if it was displayed, its neighbor takes its place.
    func deleteSpace(_ target: SpaceSession) {
        guard session.spaces.count > 1 else {
            return
        }
        if target === space, let index = session.spaces.firstIndex(where: { $0 === target }) {
            selectSpace(at: index == 0 ? 1 : index - 1)
        }
        session.deleteSpace(target)
        spacesDidChange()
    }

    /// Spaces deleted (here, in another window, by sync): their viewers are dropped; if the displayed one is gone, the
    /// window shows the first Space.
    func spacesDidChange() {
        let ids = Set(session.spaces.map(\.id))
        viewers = viewers.filter { ids.contains($0.key) }
        guard !isClosed, let currentSpaceID, !ids.contains(currentSpaceID), let first = session.spaces.first else {
            return
        }
        self.currentSpaceID = first.id
        // The window's own tabs stay; only the theme and profile shown change.
        guard windowTabs == nil else {
            return
        }
        let viewer = viewer(in: first)
        first.tabManager.activate(viewer)
        if isOpen {
            first.tabManager.setOnScreen(viewer, true)
        }
        first.tabManager.loadSelectedTab()
    }

    /// “Move to…”: the window's own tabs go into `target`, which the window now shows, on the tab it showed.
    func moveWindowTabs(to target: SpaceSession) {
        guard let tabs = windowTabs else {
            return
        }
        // Selected in this window, not in another one showing `target`.
        let viewer = viewer(in: target)
        target.tabManager.activate(viewer)
        let selected = tabs.move(to: target)
        tabs.tabManager.setOnScreen(tabs.tabManager.activeViewer, false)
        session.removeWindowTabs(tabs)
        windowTabs = nil
        currentSpaceID = target.id
        defaults?.set(target.id.uuidString, forKey: Self.currentSpaceKey)
        session.showFavorites(in: target)
        if isOpen {
            target.tabManager.setOnScreen(viewer, true)
        }
        if let selected {
            target.tabManager.setSelection(selected.id, for: viewer)
        }
        target.tabManager.loadSelectedTab()
    }

    /// “Customize…” in a folder's menu: opens its panel (closing that of another folder), or closes it if it is
    /// already open.
    func toggleFolderCustomization(_ folderID: UUID) {
        customizedFolderID = customizedFolderID == folderID ? nil : folderID
    }

    /// Copies `url` (context menu of a tab) and confirms “URL Copied” in this window.
    func copyLink(_ url: URL, to pasteboard: NSPasteboard = .general) {
        TabLinkCopier.copy(url, to: pasteboard)
        copyConfirmation.show()
        // Never the address itself.
        Logger.browser.info("Address copied")
    }

    /// ⇧⌘C and the “Copy URL” action of the command bar: the address of the frontmost page (the peek if it is open,
    /// otherwise the displayed tab). Without an address, nothing is copied or confirmed.
    @discardableResult
    func copySelectedTabURL(to pasteboard: NSPasteboard = .general) -> Bool {
        guard let url = frontTab?.displayedURL else {
            return false
        }
        copyLink(url, to: pasteboard)
        return true
    }
}

extension WindowModel {
    /// The floating sidebar stays shown while one of its presentations is open (review ON19): the pointer leaves it
    /// to use them (Space editor, folder customization and its color panel, renaming, alerts of a Space).
    var holdsFloatingSidebar: Bool {
        editedSpaceID != nil || customizedFolderID != nil || renamedSpace != nil || deletedSpace != nil
            || tabManager.renamingFolderID != nil
    }

    /// A tab of this window can leave it for a window of its own (menu, drag out): never in a private window, whose
    /// session is its own; nor the only tab of a window of its own tabs, which would close it (review ON18).
    var canOpenInNewWindow: Bool {
        !session.isPrivate && (windowTabs == nil || tabManager.tabs.count > 1)
    }
}
