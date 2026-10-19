import Foundation
import Observation
import OSLog
import SwiftData
import WebKit

/// A running Space: its record, its theme, its tabs and their automatic
/// saving.
@MainActor
@Observable
final class SpaceSession: Identifiable {
    @ObservationIgnored let record: SpaceRecord
    @ObservationIgnored let tabManager: TabManager
    @ObservationIgnored let store: SpaceStore
    @ObservationIgnored private let context: ModelContext
    /// Profile of the Space when it was opened: its tabs hold that profile's data (cookies, storage).
    @ObservationIgnored let openedProfileID: UUID?
    /// Colors of the background and of the sidebar.
    private(set) var theme: SpaceTheme

    var id: UUID {
        record.id
    }

    /// Reloads the saved tabs of the Space, then saves each change.
    /// `websiteDataStore`: data store of the Space's profile; `downloadScope`: that of the window;
    /// `sitePermissions`: permission decisions of the session, seen for the Space's profile; `siteZooms`: per-site page
    /// zoom of the session; `history`: history of the session (nil for a private window).
    init(
        record: SpaceRecord,
        context: ModelContext,
        websiteDataStore: WKWebsiteDataStore,
        services: SessionServices = SessionServices(),
        downloadScope: DownloadScope = .regular,
        sitePermissions: SitePermissionStore? = nil,
        siteZooms: SiteZoomStore? = nil,
        history: HistoryStore? = nil,
    ) {
        self.record = record
        self.context = context
        openedProfileID = record.profile?.id
        theme = SpaceTheme.decoded(from: record.themeData) ?? .default
        tabManager = TabManager(websiteDataStore: websiteDataStore, services: services, downloadScope: downloadScope)
        tabManager.sitePermissions = sitePermissions.map { SitePermissionScope(store: $0, profileID: record.profile?.id) }
        tabManager.siteZooms = siteZooms
        tabManager.history = history.map { HistoryScope(store: $0, profileID: record.profile?.id, spaceID: record.id) }
        store = SpaceStore(space: record, context: context)
        let (tabs, layout) = store.load()
        tabManager.restore(tabs: tabs, layout: layout)
        store.startAutosave(of: tabManager)
    }

    /// Changes the theme and saves it.
    func setTheme(_ newTheme: SpaceTheme) {
        theme = newTheme
        record.themeData = newTheme.encoded()
        do {
            try context.save()
        } catch {
            Logger.app.error("Theme not saved: \(error.logSummary, privacy: .public)")
        }
    }

    /// Reads the saved theme again (changed by another Mac).
    func reloadTheme() {
        let saved = SpaceTheme.decoded(from: record.themeData) ?? .default
        if saved != theme {
            theme = saved
        }
    }

    /// Icon of the Space, read from its record (observed: the sidebar follows its changes).
    var icon: SidebarIcon {
        record.icon
    }

    /// Changes the icon and saves it: an invalid symbol or emoji gives the circle, and so does `.default`. Nothing is
    /// saved if it does not change.
    func setIcon(_ newIcon: SidebarIcon) {
        // Round trip through the stored form: the same icon as the one read back at the next launch.
        let icon = SidebarIcon(spaceSymbol: newIcon.spaceSymbol)
        guard icon.spaceSymbol != record.symbol else {
            return
        }
        record.icon = icon
        do {
            try context.save()
        } catch {
            Logger.app.error("Space icon not saved: \(error.logSummary, privacy: .public)")
        }
    }

    /// Saves right away, with the navigation state of each loaded tab (app quitting).
    func saveNow() {
        tabManager.captureInteractionStates()
        store.saveNow(tabManager)
    }

    /// Space deleted: no more saving, and its Peek, today tabs and pinned tabs release their web view.
    /// The favorites, shared across the profile, stay open in the other Spaces.
    func close() {
        store.stop()
        tabManager.closePeek()
        let favorites = Set(tabManager.layout.favorites)
        for tab in tabManager.tabs where !favorites.contains(tab.id) {
            tab.unload(resettingTo: nil, title: nil)
        }
    }
}
