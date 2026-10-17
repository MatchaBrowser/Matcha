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
        try await waitUntil(timeout: .seconds(4)) { store.space.tabs?.first?.id == tab.id }
        #expect(store.space.tabs?.first?.place == .pinned)
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
