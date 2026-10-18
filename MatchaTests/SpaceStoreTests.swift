import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

@MainActor
struct SpaceStoreTests {
    private let container: ModelContainer
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    init() throws {
        container = try BrowserSchema.makeContainer(inMemory: true)
    }

    /// Profil et Space enregistrés, vides.
    private func makeStore() -> SpaceStore {
        let context = container.mainContext
        let profile = ProfileRecord(name: "Personnel")
        let space = SpaceRecord(name: "Perso", profile: profile)
        context.insert(profile)
        context.insert(space)
        return SpaceStore(space: space, context: context)
    }

    /// Favori, épinglé dans un dossier, épinglé, deux onglets du jour : tous chargés avec une page.
    private func fillManager() async throws -> [BrowserTab] {
        let tabs = (0 ..< 5).map { index in manager.newTab(url: URL(string: "about:blank#\(index)")) }
        try await waitUntil { tabs.allSatisfy { $0.url != nil && !$0.isLoading } }
        manager.setPlace(tabs[0], to: .favorite)
        manager.setPlace(tabs[1], to: .pinned)
        let folder = manager.newFolder()
        manager.renameFolder(folder, to: "Travail")
        manager.move(tabs[2], to: .pinned(folder: folder, index: 0))
        return tabs
    }

    @Test func `saved space loads back with the same layout and tabs`() async throws {
        let store = makeStore()
        _ = try await fillManager()
        store.saveNow(manager)

        let (stored, layout) = SpaceStore(space: store.space, context: container.mainContext).load()
        #expect(layout == manager.layout)
        #expect(Set(stored) == Set(manager.storedTabs()))
        #expect(store.space.profile?.favorites?.count == 1)
        #expect(store.space.tabs?.count == 4)
        #expect(store.space.folders?.first?.name == "Travail")
    }

    /// Icône et couleurs des dossiers (sous-dossiers compris) : enregistrées en texte court, relues à l'identique ;
    /// « Réinitialiser » vide les champs.
    @Test func `folder appearances are saved and loaded back`() async throws {
        let store = makeStore()
        _ = try await fillManager()
        let work = try #require(manager.layout.folderEntries.first?.id)
        let client = manager.newFolder(in: work)
        manager.setFolderAppearance(work, FolderAppearance(icon: .symbol("briefcase"), textColor: ThemeColor(rgb: 0xFF3B30)))
        manager.setFolderAppearance(
            client,
            FolderAppearance(icon: .emoji("🌿"), backgroundColor: ThemeColor(red: 0.2, green: 0.4, blue: 0.6)),
        )
        store.saveNow(manager)

        let records = Dictionary(uniqueKeysWithValues: (store.space.folders ?? []).map { ($0.id, $0) })
        #expect(records[work]?.iconValue == "symbol:briefcase")
        #expect(records[work]?.textColorHex == "#FF3B30")
        #expect(records[work]?.backgroundColorHex == nil)
        #expect(records[client]?.iconValue == "emoji:🌿")
        #expect(records[client]?.backgroundColorHex == "#336699")
        let (_, layout) = SpaceStore(space: store.space, context: container.mainContext).load()
        #expect(layout == manager.layout)

        manager.setFolderAppearance(client, .default)
        store.saveNow(manager)
        #expect(records[client]?.iconValue == nil)
        #expect(records[client]?.backgroundColorHex == nil)
        #expect(SpaceStore(space: store.space, context: container.mainContext).load().layout.pinned.folder(client)?.appearance == .default)
    }

    @Test func `closed tabs and folders are deleted but archived tabs are kept`() async throws {
        let store = makeStore()
        let tabs = try await fillManager()
        let archived = TabRecord(url: URL(string: "https://archive.test"), place: .today)
        archived.place = nil
        archived.space = store.space
        store.saveNow(manager)

        manager.close(tabs[4])
        if let folder = manager.layout.folderEntries.first?.id {
            manager.deleteFolder(folder)
        }
        store.saveNow(manager)
        let records = try container.mainContext.fetch(FetchDescriptor<TabRecord>())
        #expect(records.count == 5)
        #expect(records.contains { $0.id == archived.id })
        #expect(!records.contains { $0.id == tabs[4].id })
        #expect(try container.mainContext.fetchCount(FetchDescriptor<FolderRecord>()) == 0)
    }

    @Test func `changes are saved after a delay`() async throws {
        let store = makeStore()
        store.startAutosave(of: manager)
        let tab = manager.newTab()
        manager.setPlace(tab, to: .pinned)
        #expect(store.space.tabs?.isEmpty != false)
        // Délai par défaut (10 s) : avec tous les tests en parallèle, l'enregistrement attend le fil principal.
        try await waitUntil { store.space.tabs?.first?.id == tab.id }
        #expect(store.space.tabs?.first?.place == .pinned)
    }

    @Test func `split membership and widths are saved and loaded back`() async throws {
        let store = makeStore()
        let tabs = try await fillManager()
        manager.select(tabs[4])
        manager.openInSplit(tabs[3])
        let group = try #require(manager.displayedSplit)
        manager.setSplitFractions(group.id, [0.4, 0.6])
        store.saveNow(manager)

        let records = try Dictionary(uniqueKeysWithValues: container.mainContext.fetch(FetchDescriptor<TabRecord>()).map { ($0.id, $0) })
        #expect(records[tabs[4].id]?.splitGroupID == group.id)
        #expect(records[tabs[4].id]?.splitFraction == 0.4)
        #expect(records[tabs[3].id]?.splitGroupID == group.id)
        #expect(records[tabs[3].id]?.splitFraction == 0.6)
        for tab in tabs.prefix(3) {
            #expect(records[tab.id]?.splitGroupID == nil)
            #expect(records[tab.id]?.splitFraction == 0)
        }

        // Relance : le split revient, et chacun de ses panneaux crée sa vue web à l'affichage.
        let (stored, layout) = SpaceStore(space: store.space, context: container.mainContext).load()
        #expect(layout == manager.layout)
        let restored = TabManager(websiteDataStore: .nonPersistent())
        restored.restore(tabs: stored, layout: layout)
        #expect(restored.selectedTabID == tabs[3].id)
        restored.loadSelectedTab()
        #expect(restored.displayedTabIDs == [tabs[4].id, tabs[3].id])
        let allLoaded = restored.displayedTabs.allSatisfy(\.isLoaded)
        #expect(allLoaded)

        manager.separateSplit(group.id)
        store.saveNow(manager)
        #expect(records[tabs[4].id]?.splitGroupID == nil)
        #expect(records[tabs[3].id]?.splitFraction == 0)
    }

    @Test func `restored tabs wait to be shown before loading`() {
        let ids = (0 ..< 3).map { _ in UUID() }
        let now = Date.now
        let stored = ids.enumerated().map { index, id in
            StoredTab(id: id, url: URL(string: "about:blank#\(index)"), title: "Onglet \(index)", lastActivity: now - Double(10 - index))
        }
        var layout = SidebarLayout()
        for id in ids {
            layout.insertToday(id, at: layout.today.count)
        }
        layout.setPlace(ids[0], to: .pinned)

        manager.restore(tabs: stored, layout: layout)
        #expect(manager.layout == layout)
        // Le plus récemment utilisé est sélectionné ; rien ne se charge avant l'affichage du Space.
        #expect(manager.selectedTab?.id == ids[2])
        #expect(manager.tabs.allSatisfy { !$0.isLoaded })
        manager.loadSelectedTab()
        #expect(manager.tab(withID: ids[2])?.isLoaded == true)
        #expect(manager.tab(withID: ids[0])?.isLoaded == false)
        #expect(manager.tab(withID: ids[0])?.displayTitle == "Onglet 0")
        #expect(manager.tab(withID: ids[1])?.url == URL(string: "about:blank#1"))
    }
}
