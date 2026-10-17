import Foundation
import Observation
import OSLog
import SwiftData
import WebKit

/// Un Space en cours d'exécution : son enregistrement, son thème, ses onglets et leur enregistrement
/// automatique.
@MainActor
@Observable
final class SpaceSession: Identifiable {
    @ObservationIgnored let record: SpaceRecord
    @ObservationIgnored let tabManager: TabManager
    @ObservationIgnored let store: SpaceStore
    @ObservationIgnored private let context: ModelContext
    /// Couleurs du fond et de la barre latérale.
    private(set) var theme: SpaceTheme

    var id: UUID {
        record.id
    }

    /// Recharge les onglets enregistrés du Space et enregistre ensuite chaque changement.
    /// `websiteDataStore` : magasin de données du profil du Space ; `downloadScope` : celui de la fenêtre ;
    /// `sitePermissions` : décisions de permission de la session, vues pour le profil du Space ; `siteZooms` : zoom des
    /// pages par site de la session ; `history` : historique de la session (nil pour une fenêtre privée).
    init(
        record: SpaceRecord,
        context: ModelContext,
        websiteDataStore: WKWebsiteDataStore,
        faviconService: FaviconService = .shared,
        downloadScope: DownloadScope = .regular,
        sitePermissions: SitePermissionStore? = nil,
        siteZooms: SiteZoomStore? = nil,
        history: HistoryStore? = nil,
    ) {
        self.record = record
        self.context = context
        theme = SpaceTheme.decoded(from: record.themeData) ?? .default
        tabManager = TabManager(websiteDataStore: websiteDataStore, faviconService: faviconService, downloadScope: downloadScope)
        tabManager.sitePermissions = sitePermissions.map { SitePermissionScope(store: $0, profileID: record.profile?.id) }
        tabManager.siteZooms = siteZooms
        tabManager.history = history.map { HistoryScope(store: $0, profileID: record.profile?.id, spaceID: record.id) }
        store = SpaceStore(space: record, context: context)
        let (tabs, layout) = store.load()
        tabManager.restore(tabs: tabs, layout: layout)
        store.startAutosave(of: tabManager)
    }

    /// Change le thème et l'enregistre.
    func setTheme(_ newTheme: SpaceTheme) {
        theme = newTheme
        record.themeData = newTheme.encoded()
        do {
            try context.save()
        } catch {
            Logger.app.error("Thème non enregistré : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Enregistre tout de suite, avec l'état de navigation de chaque onglet chargé (fermeture de l'app).
    func saveNow() {
        tabManager.captureInteractionStates()
        store.saveNow(tabManager)
    }

    /// Space supprimé : plus d'enregistrement, et son aperçu, ses onglets du jour et épinglés libèrent leur vue web.
    /// Les favoris, communs au profil, restent ouverts dans les autres Spaces.
    func close() {
        store.stop()
        tabManager.closePeek()
        let favorites = Set(tabManager.layout.favorites)
        for tab in tabManager.tabs where !favorites.contains(tab.id) {
            tab.unload(resettingTo: nil, title: nil)
        }
    }
}
