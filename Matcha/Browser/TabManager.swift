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
    private var tabsByID: [BrowserTab.ID: BrowserTab] = [:]

    /// Magasin de données (cookies, stockage) des onglets de cette fenêtre.
    @ObservationIgnored let websiteDataStore: WKWebsiteDataStore
    /// Délégué de toutes les vues web de cette fenêtre (les vues ne le retiennent pas).
    @ObservationIgnored let coordinator = NavigationCoordinator()
    @ObservationIgnored let faviconService: FaviconService

    init(websiteDataStore: WKWebsiteDataStore, faviconService: FaviconService = .shared) {
        self.websiteDataStore = websiteDataStore
        self.faviconService = faviconService
        coordinator.tabManager = self
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
        tab.delegate = coordinator
        tab.makeWebViewIfNeeded()
        tabsByID[tab.id] = tab
        layout.insertToday(tab.id, at: todayInsertionIndex(after: anchor))
        if select || selectedTab == nil {
            setSelection(tab.id)
        }
        return tab
    }

    /// Ferme `tab` (⌘W, ×). Un onglet du jour disparaît. Un épinglé ou un favori reste dans la barre,
    /// comme dans Arc : il revient à son adresse d'origine et se décharge.
    /// S'il était sélectionné, son voisin suivant dans la barre prend la sélection, ou le précédent.
    func close(_ tab: BrowserTab) {
        guard let place = layout.place(of: tab.id) else {
            return
        }
        if place == .today {
            delete(tab)
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

    /// Ferme tous les onglets du jour (bouton « Effacer »). Si l'onglet sélectionné en faisait partie,
    /// la sélection passe au dernier onglet restant de la barre.
    func clearToday() {
        let cleared = todayTabs
        let selectionCleared = cleared.contains { $0.id == selectedTabID }
        cleared.forEach(discard)
        if selectionCleared {
            setSelection(layout.orderedTabIDs.last)
        }
    }

    /// Ouvre une copie de l'onglet juste après lui, avec son historique, et la sélectionne.
    @discardableResult
    func duplicate(_ tab: BrowserTab) -> BrowserTab {
        // Même configuration : même profil. L'état d'interaction emporte l'historique précédent/suivant.
        let copy = insertTab(configuration: tab.configuration, after: tab, select: true)
        if let state = tab.webView?.interactionState {
            copy.webView?.interactionState = state
        } else if let url = tab.url {
            copy.load(url)
        }
        return copy
    }

    /// Ferme tous les onglets du jour sauf `tab`, qui est sélectionné ; épinglés et favoris restent.
    func closeOtherTabs(than tab: BrowserTab) {
        select(tab)
        for other in todayTabs where other !== tab {
            close(other)
        }
    }

    /// Sélectionne l'onglet ; un onglet déchargé recharge alors sa page.
    func select(_ tab: BrowserTab) {
        guard tabsByID[tab.id] != nil else {
            return
        }
        setSelection(tab.id)
    }

    /// Range l'onglet dans les favoris, les épinglés (à la fin) ou les onglets du jour (en tête).
    func setPlace(_ tab: BrowserTab, to place: TabPlace) {
        guard tabsByID[tab.id] != nil else {
            return
        }
        let previous = layout.place(of: tab.id)
        layout.setPlace(tab.id, to: place)
        updatePinnedOrigin(of: tab, previousPlace: previous)
    }

    /// Déplace l'onglet dans la barre (glisser-déposer).
    func move(_ tab: BrowserTab, to destination: SidebarDestination) {
        guard tabsByID[tab.id] != nil else {
            return
        }
        let previous = layout.place(of: tab.id)
        layout.move(tab.id, to: destination)
        updatePinnedOrigin(of: tab, previousPlace: previous)
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

    /// Seul point d'entrée des extensions pour modifier le rangement.
    func updateLayout(_ change: (inout SidebarLayout) -> Void) {
        change(&layout)
    }

    /// Un onglet qui devient épinglé ou favori retient son adresse et son titre actuels comme origine ;
    /// redevenu onglet du jour, il les oublie.
    private func updatePinnedOrigin(of tab: BrowserTab, previousPlace: TabPlace?) {
        if layout.place(of: tab.id) == .today {
            tab.pinnedURL = nil
            tab.pinnedTitle = nil
        } else if previousPlace == .today || tab.pinnedURL == nil {
            tab.pinnedURL = tab.url
            tab.pinnedTitle = tab.title
        }
    }

    /// Sélectionne `id`, note son activité et s'assure que sa vue web existe.
    func setSelection(_ id: BrowserTab.ID?) {
        // L'onglet qui quitte l'écran retient son état de navigation.
        if let previous = selectedTab, previous.id != id {
            previous.captureInteractionState()
        }
        selectedTabID = id
        if let id, let tab = tabsByID[id] {
            tab.lastActivity = .now
            tab.makeWebViewIfNeeded()
        }
    }

    /// Applique `change` à `tab` ; s'il était sélectionné, la sélection passe à son voisin suivant
    /// dans la barre, ou au précédent s'il était le dernier.
    func moveSelection(awayFrom tab: BrowserTab, during change: () -> Void) {
        let ordered = layout.orderedTabIDs
        let index = ordered.firstIndex(of: tab.id)
        let wasSelected = selectedTabID == tab.id
        change()
        guard wasSelected, let index else {
            return
        }
        let others = layout.orderedTabIDs.filter { $0 != tab.id }
        setSelection(others.isEmpty ? nil : others[min(index, others.count - 1)])
    }

    private func discard(_ tab: BrowserTab) {
        layout.remove(tab.id)
        tabsByID[tab.id] = nil
        tab.stop()
    }

    private func todayInsertionIndex(after anchor: BrowserTab?) -> Int {
        guard let anchor, var index = layout.today.firstIndex(of: anchor.id) else {
            return 0
        }
        index += 1
        while index < layout.today.count, tabsByID[layout.today[index]]?.openerID == anchor.id {
            index += 1
        }
        return index
    }
}
