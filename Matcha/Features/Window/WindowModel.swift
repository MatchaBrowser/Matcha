import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

/// State of a window: the displayed Space, the edge from which the chosen Space arrives (animation), the “URL Copied”
/// confirmation, the downloads list, the site settings panel and the folder customization panel.
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
    /// Import from Arc started from this window (task 7.1).
    let arcImport = ArcImportModel()
    /// Where to remember the displayed Space from one launch to the next; nil to remember nothing (tests).
    @ObservationIgnored private let defaults: UserDefaults?

    init(session: BrowserSession, defaults: UserDefaults?) {
        self.session = session
        self.defaults = defaults
        currentSpaceID = defaults?.string(forKey: Self.currentSpaceKey).flatMap(UUID.init(uuidString:))
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

    /// Shows `target`, which takes back and now holds the favorites of its profile.
    func select(_ target: SpaceSession) {
        let current = space
        guard target !== current, let targetIndex = session.spaces.firstIndex(where: { $0 === target }) else {
            return
        }
        // The displayed tabs (the whole split) leave the screen: they remember their navigation state; their peek
        // closes.
        current.tabManager.displayedTabs.forEach { $0.captureInteractionState() }
        current.tabManager.closePeek()
        // It takes back the favorites of its profile, held until then by another Space.
        session.showFavorites(in: target)
        transitionEdge = targetIndex > spaceIndex ? .trailing : .leading
        // A Space's popover does not survive a Space change (except `editSpace`, which reopens it).
        editedSpaceID = nil
        currentSpaceID = target.id
        defaults?.set(target.id.uuidString, forKey: Self.currentSpaceKey)
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

    /// Sends the tab of the displayed Space to `target`. Same profile: the tab keeps its page and its history. Other
    /// profile: it is recreated from its address, with the cookies of that profile.
    func move(_ tab: BrowserTab, to target: SpaceSession) {
        let source = space
        guard target !== source else {
            return
        }
        if target.record.profile?.id == source.record.profile?.id {
            if let detached = source.tabManager.detach(tab) {
                target.tabManager.attach(detached)
            }
        } else {
            let url = tab.url
            source.tabManager.delete(tab)
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
        Logger.browser.info("Adresse copiée")
    }

    /// ⇧⌘C and the “Copy URL” action of the command bar: the address of the frontmost page (the peek if it is open,
    /// otherwise the displayed tab). Without an address, nothing is copied or confirmed.
    @discardableResult
    func copySelectedTabURL(to pasteboard: NSPasteboard = .general) -> Bool {
        guard let url = space.tabManager.frontTab?.url else {
            return false
        }
        copyLink(url, to: pasteboard)
        return true
    }
}
