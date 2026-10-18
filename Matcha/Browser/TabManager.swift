import Foundation
import Observation
import WebKit

/// Onglets d'une fenêtre, leur rangement dans la barre latérale et l'onglet sélectionné.
@MainActor
@Observable
final class TabManager {
    /// Place et ordre des onglets dans la barre latérale (en mémoire jusqu'à la phase 3).
    private(set) var layout = SidebarLayout()
    private(set) var selectedTabID: BrowserTab.ID?
    /// Dossier dont le nom est en cours de saisie dans la barre (état d'interface).
    var renamingFolderID: UUID?
    /// Aperçu ouvert par-dessus les pages affichées (Maj+clic, tâche 4.4) : une page hors de la barre latérale.
    private(set) var peek: Peek?
    private var tabsByID: [BrowserTab.ID: BrowserTab] = [:]

    /// Magasin de données (cookies, stockage) des onglets de cette fenêtre.
    @ObservationIgnored let websiteDataStore: WKWebsiteDataStore
    /// Délégué de toutes les vues web de cette fenêtre (les vues ne le retiennent pas).
    @ObservationIgnored let coordinator = NavigationCoordinator()
    @ObservationIgnored let faviconService: FaviconService
    /// Fenêtre à laquelle reviennent les téléchargements de ces onglets : celle d'une fenêtre privée les oublie.
    @ObservationIgnored let downloadScope: DownloadScope
    /// Décisions de permission du profil de ces onglets (tâche 5.2), données par le Space ; nil : rien n'est retenu.
    @ObservationIgnored var sitePermissions: SitePermissionScope?
    /// Zoom des pages par site (tâche 5.4), donné par le Space : celui de la session ; nil : rien n'est retenu.
    @ObservationIgnored var siteZooms: SiteZoomStore?
    /// Historique des pages de ce Space (tâche 5.5), donné par le Space ; nil : rien n'est retenu (fenêtre privée).
    @ObservationIgnored var history: HistoryScope?
    /// Ce qui est affiché dans les fenêtres de la session (tâches 5.6 et 5.7), donné par la session.
    @ObservationIgnored weak var lifecycle: TabLifecycleService?

    init(websiteDataStore: WKWebsiteDataStore, faviconService: FaviconService = .shared, downloadScope: DownloadScope = .regular) {
        self.websiteDataStore = websiteDataStore
        self.faviconService = faviconService
        self.downloadScope = downloadScope
        coordinator.tabHost = self
    }

    /// Tous les onglets, dans l'ordre de la barre latérale.
    var tabs: [BrowserTab] {
        layout.orderedTabIDs.compactMap { tabsByID[$0] }
    }

    var favoriteTabs: [BrowserTab] {
        layout.favorites.compactMap { tabsByID[$0] }
    }

    var todayTabs: [BrowserTab] {
        layout.today.compactMap { tabsByID[$0] }
    }

    var selectedTab: BrowserTab? {
        selectedTabID.flatMap { tabsByID[$0] }
    }

    func tab(withID id: BrowserTab.ID) -> BrowserTab? {
        tabsByID[id]
    }

    /// Onglet qui possède `webView`.
    func tab(for webView: WKWebView) -> BrowserTab? {
        tabsByID.values.first { $0.webView === webView }
    }

    func place(of tab: BrowserTab) -> TabPlace? {
        layout.place(of: tab.id)
    }

    /// Ouvre un onglet en tête des onglets du jour et y charge `url` si elle est fournie.
    @discardableResult
    func newTab(url: URL? = nil, select: Bool = true) -> BrowserTab {
        let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: websiteDataStore)
        let tab = insertTab(configuration: configuration, after: nil, select: select)
        if let url {
            tab.load(url)
        }
        return tab
    }

    /// Insère parmi les onglets du jour un onglet dont la vue web est créée avec `configuration`, telle
    /// quelle : c'est ce qu'exige WebKit pour les fenêtres ouvertes par une page.
    /// Si `anchor` est un onglet du jour, le nouveau va après lui et après les onglets déjà ouverts
    /// depuis lui, pour garder l'ordre des clics ; sinon, en tête.
    /// Il est sélectionné si `select` est vrai ou si aucun onglet ne l'est.
    @discardableResult
    func insertTab(configuration: WKWebViewConfiguration, after anchor: BrowserTab?, select: Bool) -> BrowserTab {
        let tab = BrowserTab(configuration: configuration, openerID: anchor?.id)
        insert(tab, after: anchor, select: select)
        return tab
    }

    /// Range parmi les onglets du jour un onglet déjà créé (aperçu ouvert en onglet ; tâche 4.5 : « Ouvrir dans
    /// le Space »), comme `insertTab`.
    func insert(_ tab: BrowserTab, after anchor: BrowserTab?, select: Bool) {
        tab.delegate = coordinator
        tab.makeWebViewIfNeeded()
        tabsByID[tab.id] = tab
        layout.insertToday(tab.id, at: todayInsertionIndex(after: anchor))
        if select || selectedTab == nil {
            setSelection(tab.id)
        }
    }

    /// Ferme `tab` (⌘W, ×). Un onglet du jour disparaît. Un épinglé ou un favori reste dans la barre,
    /// comme dans Arc : il revient à son adresse d'origine et se décharge ; un split épinglé se ferme en entier.
    /// S'il était sélectionné, son voisin dans le split prend la sélection, sinon son voisin suivant dans la
    /// barre, ou le précédent.
    func close(_ tab: BrowserTab) {
        guard let place = layout.place(of: tab.id) else {
            return
        }
        if place == .today {
            delete(tab)
        } else if place == .pinned, let group = layout.split(containing: tab.id) {
            // Un split épinglé se ferme en entier, comme un épinglé : il se décharge et reste dans la barre.
            closeSplit(group.id)
        } else {
            moveSelection(awayFrom: tab) {
                tab.unload(resettingTo: tab.pinnedURL, title: tab.pinnedTitle)
            }
        }
    }

    /// Retire l'onglet de la barre, où qu'il soit, et libère sa vue web.
    func delete(_ tab: BrowserTab) {
        guard tabsByID[tab.id] != nil else {
            return
        }
        moveSelection(awayFrom: tab) { discard(tab) }
    }

    /// Sélectionne l'onglet ; un onglet déchargé recharge alors sa page.
    func select(_ tab: BrowserTab) {
        guard tabsByID[tab.id] != nil else {
            return
        }
        setSelection(tab.id)
    }

    /// Range l'onglet dans les favoris, les épinglés (à la fin) ou les onglets du jour (en tête) ; il quitte
    /// son split, dont le reste reste affiché.
    func setPlace(_ tab: BrowserTab, to place: TabPlace) {
        guard tabsByID[tab.id] != nil else {
            return
        }
        keepingPanesOnScreen(leaving: tab) {
            let previous = layout.place(of: tab.id)
            layout.setPlace(tab.id, to: place)
            updatePinnedOrigin(of: tab, previousPlace: previous)
        }
    }

    /// Déplace l'onglet dans la barre (glisser-déposer) ; il quitte son split, dont le reste reste affiché.
    func move(_ tab: BrowserTab, to destination: SidebarDestination) {
        guard tabsByID[tab.id] != nil else {
            return
        }
        keepingPanesOnScreen(leaving: tab) {
            let previous = layout.place(of: tab.id)
            layout.move(tab.id, to: destination)
            updatePinnedOrigin(of: tab, previousPlace: previous)
        }
    }

    // MARK: Primitives des extensions

    /// Ajoute un onglet existant (restauré ou venu d'un autre Space), branché sur le délégué de ce Space.
    func register(_ tab: BrowserTab) {
        tab.delegate = coordinator
        tabsByID[tab.id] = tab
    }

    /// Oublie un onglet sans le fermer (il continue d'exister ailleurs).
    func unregister(_ id: BrowserTab.ID) {
        tabsByID[id] = nil
    }

    /// Sélectionne `id` sans charger sa page (restauration).
    func restoreSelection(_ id: BrowserTab.ID?) {
        selectedTabID = id
    }

    /// Primitive de `TabManager+Peek` : remplace l'aperçu, sans rien libérer.
    func setPeek(_ newPeek: Peek?) {
        peek = newPeek
    }

    /// Seul point d'entrée des extensions pour modifier le rangement.
    func updateLayout(_ change: (inout SidebarLayout) -> Void) {
        change(&layout)
    }

    /// Un onglet qui devient épinglé ou favori retient son adresse et son titre actuels comme origine ;
    /// redevenu onglet du jour, il les oublie.
    func updatePinnedOrigin(of tab: BrowserTab, previousPlace: TabPlace?) {
        if layout.place(of: tab.id) == .today {
            tab.pinnedURL = nil
            tab.pinnedTitle = nil
        } else if previousPlace == .today || tab.pinnedURL == nil {
            tab.pinnedURL = tab.url
            tab.pinnedTitle = tab.title
        }
    }

    /// Sélectionne `id`, note son activité et s'assure que la vue web de chaque onglet affiché existe
    /// (tout son split).
    func setSelection(_ id: BrowserTab.ID?) {
        // L'aperçu appartient à l'onglet affiché : en afficher un autre le ferme (tâche 4.4).
        if let peek, peek.sourceTabID != id {
            closePeek()
        }
        // Les onglets qui quittent l'écran retiennent leur état de navigation.
        let leaving = displayedTabs
        selectedTabID = id
        let shown = displayedTabs
        for tab in leaving where !shown.contains(where: { $0 === tab }) {
            tab.captureInteractionState()
        }
        if let id {
            tabsByID[id]?.lastActivity = .now
        }
        shown.forEach { $0.makeWebViewIfNeeded() }
    }

    /// Applique `change` à `tab` ; s'il était sélectionné, la sélection passe à son voisin dans le split,
    /// sinon à son voisin suivant dans la barre, ou au précédent s'il était le dernier.
    func moveSelection(awayFrom tab: BrowserTab, during change: () -> Void) {
        moveSelection(awayFrom: [tab.id], preferring: layout.split(containing: tab.id)?.neighbor(of: tab.id), during: change)
    }

    /// Applique `change` ; si l'onglet sélectionné fait partie de `ids`, la sélection passe à `preferred` s'il est
    /// encore rangé, sinon au premier onglet hors de `ids` qui le suivait dans la barre, sinon au dernier qui le précédait.
    func moveSelection(awayFrom ids: Set<BrowserTab.ID>, preferring preferred: BrowserTab.ID? = nil, during change: () -> Void) {
        let ordered = layout.orderedTabIDs
        let index = selectedTabID.flatMap { ordered.firstIndex(of: $0) }
        let wasSelected = selectedTabID.map(ids.contains) ?? false
        change()
        guard wasSelected, let index else {
            return
        }
        if let preferred, !ids.contains(preferred), layout.place(of: preferred) != nil {
            setSelection(preferred)
            return
        }
        func remains(_ id: UUID) -> Bool {
            !ids.contains(id) && layout.place(of: id) != nil
        }
        setSelection(ordered[index...].first(where: remains) ?? ordered[..<index].last(where: remains))
    }

    func discard(_ tab: BrowserTab) {
        layout.remove(tab.id)
        tabsByID[tab.id] = nil
        tab.permissionPrompts.denyAll()
        tab.stop()
    }

    /// Après l'ancre (après son split s'il en a un) et les onglets déjà ouverts depuis elle ; en tête sans ancre
    /// du jour.
    private func todayInsertionIndex(after anchor: BrowserTab?) -> Int {
        guard let anchor, var index = layout.today.firstIndex(of: layout.split(containing: anchor.id)?.tabIDs.last ?? anchor.id) else {
            return 0
        }
        index += 1
        while index < layout.today.count, tabsByID[layout.today[index]]?.openerID == anchor.id {
            index += 1
        }
        return index
    }
}
