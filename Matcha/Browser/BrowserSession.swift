import AppKit
import Foundation
import Observation
import OSLog
import SwiftData
import WebKit

/// Données du navigateur pour toute l'app : profils et Spaces avec leurs onglets, enregistrés dans SwiftData.
@MainActor
@Observable
final class BrowserSession {
    /// Noms créés au premier lancement, dans la langue de l'utilisateur ; ce sont ensuite ses données.
    static var defaultProfileName: String {
        String(localized: "Personal", comment: "Name of the profile created at first launch")
    }

    /// La clé diffère du texte anglais pour ne pas se confondre avec le bouton « Home » (page d'accueil).
    static var defaultSpaceName: String {
        String(localized: "Home Space", defaultValue: "Home", comment: "Name of the Space created at first launch")
    }

    /// Argument de lancement pour une base en mémoire (tests d'interface) : rien n'est écrit sur disque.
    static let inMemoryStoreKey = "inMemoryStore"
    /// Argument de lancement pour une base nommée à part (tests d'interface de l'enregistrement).
    static let storeNameKey = "storeName"
    /// Argument de lancement qui vide la base nommée avant de l'ouvrir ; jamais la base par défaut.
    static let resetStoreKey = "resetStore"

    @ObservationIgnored let container: ModelContainer
    /// Session d'une fenêtre privée : rien n'est gardé (ni onglets, ni cookies, ni icônes, ni historique : `history`
    /// est nil).
    @ObservationIgnored let isPrivate: Bool
    /// Icônes de sites : cache disque partagé, ou en mémoire seulement pour une fenêtre privée.
    @ObservationIgnored let faviconService: FaviconService
    /// Téléchargements de cette session : ceux d'une fenêtre privée quittent la liste à sa fermeture (tâche 5.1).
    @ObservationIgnored let downloadScope: DownloadScope
    /// Décisions de permission des sites (tâche 5.2) : enregistrées, ou en mémoire seulement pour une fenêtre privée.
    @ObservationIgnored let sitePermissions: SitePermissionStore
    /// Zoom des pages par site (tâche 5.4) : enregistré dans les réglages, ou en mémoire seulement pour une fenêtre
    /// privée ou une base de test.
    @ObservationIgnored let siteZooms: SiteZoomStore
    /// Historique de navigation (tâche 5.5) ; nil pour une fenêtre privée : rien n'est retenu.
    @ObservationIgnored let history: HistoryStore?
    /// Mise en veille des onglets cachés (tâche 5.6), lancée par l'ouverture de la fenêtre ; mêmes règles en fenêtre
    /// privée.
    @ObservationIgnored let tabLifecycle = TabLifecycleService()
    /// Fenêtres de connexion ouvertes par les pages de la session (tâche 5.8) : privées et fermées avec elle pour une
    /// fenêtre privée.
    @ObservationIgnored let popupWindows: PopupWindowManager
    /// Bloqueur (tâche 6.2) : celui de l'app, avec les exceptions enregistrées ; celles changées dans une fenêtre privée
    /// ou une base de test restent en mémoire.
    @ObservationIgnored let contentBlocking: ContentBlockerScope
    private(set) var spaces: [SpaceSession] = []
    private(set) var profiles: [ProfileRecord] = []
    /// Magasin de données (cookies, stockage) de chaque profil, par identifiant de profil.
    @ObservationIgnored private var dataStores: [UUID: WKWebsiteDataStore] = [:]
    /// Space qui tient les favoris de chaque profil (`BrowserSession+Favorites`).
    @ObservationIgnored var favoritesHolders: [UUID: WeakTabManager] = [:]
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?

    /// Ouvre les Spaces enregistrés ; au premier lancement, crée le profil « Personnel » et le Space « Perso »
    /// (« Personal » et « Home » en anglais).
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

    /// Session de l'app. Pendant les tests, la base reste en mémoire : les onglets de l'utilisateur
    /// ne sont ni lus ni modifiés.
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
            Logger.app.error("Base indisponible, onglets non enregistrés : \(error.localizedDescription, privacy: .public)")
            // Une base en mémoire permet au moins de naviguer.
            // swiftlint:disable:next force_try
            return BrowserSession(container: try! BrowserSchema.makeContainer(inMemory: true))
        }
    }

    /// Vrai pour une base en mémoire (tests) : rien de ce qui concerne l'utilisateur ne doit être retenu.
    var isInMemory: Bool {
        container.configurations.allSatisfy(\.isStoredInMemoryOnly)
    }

    /// Magasin de données du profil : un par profil, pour que cookies et connexions ne se mélangent pas.
    /// Avec une base de test, il n'écrit rien sur disque.
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

    /// Oublie le magasin d'un profil supprimé.
    func forgetDataStore(of profileID: UUID) {
        dataStores[profileID] = nil
    }

    /// Magasins de tous les profils (effacement des cookies).
    func allDataStores() -> [WKWebsiteDataStore] {
        profiles.map(dataStore(for:))
    }

    /// Recharge la liste des profils, dans leur ordre.
    func refreshProfiles() {
        let descriptor = FetchDescriptor<ProfileRecord>(sortBy: [SortDescriptor(\.order)])
        profiles = (try? container.mainContext.fetch(descriptor)) ?? []
    }

    /// Supprime les magasins de données qui n'appartiennent plus à aucun profil (profil supprimé alors
    /// qu'une vue web l'utilisait encore).
    func removeOrphanDataStores() async {
        guard !isInMemory else {
            return
        }
        let known = Set(profiles.map(\.id))
        for identifier in await WKWebsiteDataStore.allDataStoreIdentifiers where !known.contains(identifier) {
            try? await WKWebsiteDataStore.remove(forIdentifier: identifier)
        }
    }

    /// Session d'une fenêtre privée : base en mémoire, magasins de données non persistants.
    static func makePrivate() -> BrowserSession {
        // swiftlint:disable:next force_try
        BrowserSession(container: try! BrowserSchema.makeContainer(inMemory: true), isPrivate: true)
    }

    /// Enregistre tout de suite chaque Space (fermeture de l'app).
    func saveAll() {
        spaces.forEach { $0.saveNow() }
    }

    func appendSpace(_ space: SpaceSession) {
        connect(space)
        spaces.append(space)
    }

    /// Les onglets du Space suivent la mise en veille et le bloqueur de la session, et y ouvrent leurs fenêtres de
    /// connexion.
    private func connect(_ space: SpaceSession) {
        space.tabManager.lifecycle = tabLifecycle
        space.tabManager.popupWindows = popupWindows
        space.tabManager.contentBlocking = contentBlocking
        // Seul le Space qui tient les favoris du profil les enregistre.
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

    /// Supprime les fichiers de la base `name` (`<name>.store`, `-shm`, `-wal`) dans Application Support.
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
