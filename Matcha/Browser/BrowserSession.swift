import AppKit
import Foundation
import Observation
import OSLog
import SwiftData
import WebKit

/// Browser data for the whole app: profiles and Spaces with their tabs, saved in SwiftData.
@MainActor
@Observable
final class BrowserSession {
    /// Names created at first launch, in the user's language; after that they are the user's data.
    static var defaultProfileName: String {
        String(localized: "Personal", comment: "Name of the profile created at first launch")
    }

    /// The key differs from the English text so it is not confused with the “Home” button (home page).
    static var defaultSpaceName: String {
        String(localized: "Home Space", defaultValue: "Home", comment: "Name of the Space created at first launch")
    }

    /// Launch argument for an in-memory store (UI tests): nothing is written to disk.
    static let inMemoryStoreKey = "inMemoryStore"
    /// Launch argument for a separately named store (UI tests of saving).
    static let storeNameKey = "storeName"
    /// Launch argument that empties the named store before opening it; never the default store.
    static let resetStoreKey = "resetStore"

    @ObservationIgnored let container: ModelContainer
    /// Session of a private window: nothing is kept (no tabs, cookies, icons or history: `history` is nil).
    @ObservationIgnored let isPrivate: Bool
    /// Site icons: shared disk cache, or in memory only for a private window.
    @ObservationIgnored let faviconService: FaviconService
    /// Downloads of this session: those of a private window leave the list when it closes (task 5.1).
    @ObservationIgnored let downloadScope: DownloadScope
    /// Site permission decisions (task 5.2): saved, or in memory only for a private window.
    @ObservationIgnored let sitePermissions: SitePermissionStore
    /// Page zoom per site (task 5.4): saved in the settings, or in memory only for a private window or a test
    /// store.
    @ObservationIgnored let siteZooms: SiteZoomStore
    /// Browsing history (task 5.5); nil for a private window: nothing is remembered.
    @ObservationIgnored let history: HistoryStore?
    /// Sleeping of hidden tabs (task 5.6), started when the window opens; same rules in a private window.
    @ObservationIgnored let tabLifecycle = TabLifecycleService()
    /// Sign-in windows opened by the session's pages (task 5.8): private, and closed with it, for a private window.
    @ObservationIgnored let popupWindows: PopupWindowManager
    /// Blocker (task 6.2): the app's, with the saved exceptions; those changed in a private window or a test store
    /// stay in memory.
    @ObservationIgnored let contentBlocking: ContentBlockerScope
    private(set) var spaces: [SpaceSession] = []
    private(set) var profiles: [ProfileRecord] = []
    /// Data store (cookies, storage) of each profile, by profile identifier.
    @ObservationIgnored private var dataStores: [UUID: WKWebsiteDataStore] = [:]
    /// Space that holds the favorites of each profile (`BrowserSession+Favorites`).
    @ObservationIgnored var favoritesHolders: [UUID: WeakTabManager] = [:]
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?

    /// Opens the saved Spaces; at first launch, creates the “Personal” profile and the “Home” Space (“Personnel” and
    /// “Perso” in French).
    init(container: ModelContainer, isPrivate: Bool = false, contentBlocker: ContentBlockerService = .shared) {
        self.container = container
        self.isPrivate = isPrivate
        faviconService = isPrivate ? FaviconService(directory: nil) : .shared
        downloadScope = isPrivate ? .privateWindow(UUID()) : .regular
        let context = container.mainContext
        sitePermissions = SitePermissionStore(context: isPrivate ? nil : context)
        let isInMemory = container.configurations.allSatisfy(\.isStoredInMemoryOnly)
        siteZooms = SiteZoomStore(defaults: isPrivate || isInMemory ? nil : .standard)
        history = isPrivate ? nil : HistoryStore(container: container)
        popupWindows = PopupWindowManager(
            faviconService: faviconService,
            downloadScope: downloadScope,
            siteZooms: siteZooms,
            isPrivate: isPrivate,
        )
        contentBlocking = ContentBlockerScope(service: contentBlocker, savesExceptions: !isPrivate && !isInMemory)
        popupWindows.contentBlocking = contentBlocking
        var records = (try? context.fetch(FetchDescriptor<SpaceRecord>(sortBy: [SortDescriptor(\.order)]))) ?? []
        if records.isEmpty {
            records = [Self.createDefaultSpace(in: context)]
        }
        refreshProfiles()
        spaces = records.map { record in
            SpaceSession(
                record: record,
                context: context,
                websiteDataStore: dataStore(for: record.profile),
                faviconService: faviconService,
                downloadScope: downloadScope,
                sitePermissions: sitePermissions,
                siteZooms: siteZooms,
                history: history,
            )
        }
        tabLifecycle.session = self
        spaces.forEach(connect)
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveAll() }
        }
    }

    /// The app's session. During tests, the store stays in memory: the user's tabs are neither read nor
    /// modified.
    static func launch(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> BrowserSession {
        let isUnitTesting = environment["XCTestConfigurationFilePath"] != nil
        let inMemory = isUnitTesting || defaults.bool(forKey: inMemoryStoreKey)
        let name = defaults.string(forKey: storeNameKey)
        if let name, defaults.bool(forKey: resetStoreKey) {
            deleteStore(named: name)
        }
        do {
            return try BrowserSession(container: BrowserSchema.makeContainer(inMemory: inMemory, name: name))
        } catch {
            Logger.app.error("Base indisponible, onglets non enregistrés : \(error.logSummary, privacy: .public)")
            // An in-memory store at least allows browsing.
            // swiftlint:disable:next force_try
            return BrowserSession(container: try! BrowserSchema.makeContainer(inMemory: true))
        }
    }

    /// True for an in-memory store (tests): nothing about the user must be remembered.
    var isInMemory: Bool {
        container.configurations.allSatisfy(\.isStoredInMemoryOnly)
    }

    /// The profile's data store: one per profile, so that cookies and sign-ins do not mix.
    /// With a test store, it writes nothing to disk.
    func dataStore(for profile: ProfileRecord?) -> WKWebsiteDataStore {
        guard let id = profile?.id else {
            return isInMemory ? .nonPersistent() : .default()
        }
        if let store = dataStores[id] {
            return store
        }
        let store = isInMemory ? WKWebsiteDataStore.nonPersistent() : WKWebsiteDataStore(forIdentifier: id)
        dataStores[id] = store
        return store
    }

    /// Forgets the store of a deleted profile.
    func forgetDataStore(of profileID: UUID) {
        dataStores[profileID] = nil
    }

    /// Stores of all profiles (clearing cookies).
    func allDataStores() -> [WKWebsiteDataStore] {
        profiles.map(dataStore(for:))
    }

    /// Reloads the list of profiles, in their order.
    func refreshProfiles() {
        let descriptor = FetchDescriptor<ProfileRecord>(sortBy: [SortDescriptor(\.order)])
        profiles = (try? container.mainContext.fetch(descriptor)) ?? []
    }

    /// Deletes the data stores that no longer belong to any profile (profile deleted while a web view was
    /// still using it).
    func removeOrphanDataStores() async {
        guard !isInMemory else {
            return
        }
        let known = Set(profiles.map(\.id))
        for identifier in await WKWebsiteDataStore.allDataStoreIdentifiers where !known.contains(identifier) {
            try? await WKWebsiteDataStore.remove(forIdentifier: identifier)
        }
    }

    /// Session of a private window: in-memory store, non-persistent data stores.
    static func makePrivate() -> BrowserSession {
        // swiftlint:disable:next force_try
        BrowserSession(container: try! BrowserSchema.makeContainer(inMemory: true), isPrivate: true)
    }

    /// Saves each Space right away (app quitting).
    func saveAll() {
        spaces.forEach { $0.saveNow() }
    }

    func appendSpace(_ space: SpaceSession) {
        connect(space)
        spaces.append(space)
    }

    /// The Space's tabs follow the session's tab sleeping and blocker, and open their sign-in windows in it.
    private func connect(_ space: SpaceSession) {
        space.tabManager.lifecycle = tabLifecycle
        space.tabManager.popupWindows = popupWindows
        space.tabManager.contentBlocking = contentBlocking
        // Only the Space that holds the profile's favorites saves them.
        space.store.savesFavorites = { [weak self, weak space] in
            guard let self, let space else {
                return false
            }
            return holdsFavorites(space)
        }
    }

    func removeSpace(_ space: SpaceSession) {
        spaces.removeAll { $0 === space }
    }

    /// Sorts the Spaces in the order of their records (equal ranks: the identifier breaks the tie).
    func sortSpaces() {
        spaces.sort { ($0.record.order, $0.id.uuidString) < ($1.record.order, $1.id.uuidString) }
    }

    /// Deletes the files of store `name` (`<name>.store`, `-shm`, `-wal`) in Application Support.
    private static func deleteStore(named name: String) {
        let manager = FileManager.default
        guard let directory = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let files = try? manager.contentsOfDirectory(atPath: directory.path)
        else {
            return
        }
        for file in files where file.hasPrefix("\(name).store") {
            try? manager.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    private static func createDefaultSpace(in context: ModelContext) -> SpaceRecord {
        let profile = (try? context.fetch(FetchDescriptor<ProfileRecord>()))?.first ?? {
            let profile = ProfileRecord(name: defaultProfileName)
            context.insert(profile)
            return profile
        }()
        let space = SpaceRecord(name: defaultSpaceName, profile: profile)
        context.insert(space)
        try? context.save()
        return space
    }
}
