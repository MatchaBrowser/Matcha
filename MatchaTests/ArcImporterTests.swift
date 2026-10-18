import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Import d'une barre d'Arc dans une session en mémoire (tâche 7.1) : Spaces, dossiers, épinglés, onglets ouverts,
/// profils, favoris.
@MainActor
struct ArcImporterTests {
    private let session: BrowserSession
    private let sidebar: ArcSidebar

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let url = try #require(Bundle(for: TestPages.self).url(forResource: "arc-sidebar-sample.json", withExtension: nil))
        sidebar = try ArcSidebarParser.parse(Data(contentsOf: url))
    }

    private func importer() -> ArcImporter {
        var importer = ArcImporter(session: session, displayedSpace: session.spaces.first)
        importer.symbolExists = { ["star.fill"].contains($0) }
        return importer
    }

    private func pinnedRecords(of space: SpaceSession) -> [TabRecord] {
        (space.record.tabs ?? []).filter { $0.place == .pinned }
    }

    @Test func `each Arc space becomes a new Space with its pinned items and folders`() throws {
        let before = session.spaces.count
        let (summary, spaces) = importer().importSidebar(sidebar, options: ArcImportOptions())

        #expect(spaces.map(\.record.name) == ["Perso", "Travail", "Space \(before + 3)"])
        #expect(session.spaces.count == before + 3)
        #expect(summary == ImportSummary(profiles: 1, spaces: 3, folders: 2, tabs: 4, favorites: 3))

        let perso = spaces[0]
        #expect(perso.record.symbol == "star.fill")
        #expect(SpaceTheme.decoded(from: perso.record.themeData)?.colors.first == ThemeColor(red: 0.4, green: 0.5, blue: 0.6))
        #expect(spaces[1].record.symbol == "emoji:🍵")
        let pinned = pinnedRecords(of: perso)
        #expect(Set(pinned.compactMap(\.pinnedTitle)) == ["Page A", "Renommé", "example.com"])
        let folders = perso.record.folders ?? []
        let outer = try #require(folders.first { $0.name == "Dossier" })
        let inner = try #require(folders.first { $0.name == "Sous-dossier" })
        #expect(outer.parent == nil)
        #expect(inner.parent === outer)
        #expect(pinned.first { $0.pinnedTitle == "Renommé" }?.folder === outer)
        #expect(pinned.first { $0.pinnedTitle == "example.com" }?.folder === inner)
        // Le Space ouvert a repris son contenu enregistré.
        #expect(perso.tabManager.tabs.count(where: { $0.pinnedURL != nil && $0.pinnedTitle != "Mail" && $0.pinnedTitle != "Agenda" }) == 3)
        // Rien ne se charge de lui-même : aucun onglet importé n'est sélectionné.
        #expect(perso.tabManager.selectedTab == nil)
        // Onglets ouverts : pas par défaut.
        #expect((perso.record.tabs ?? []).filter { $0.place == .today }.isEmpty)
    }

    @Test func `open tabs are imported on request`() {
        let (summary, spaces) = importer().importSidebar(sidebar, options: ArcImportOptions(includesOpenTabs: true))
        let today = (spaces[0].record.tabs ?? []).filter { $0.place == .today }.sorted { $0.order < $1.order }
        #expect(today.compactMap(\.title) == ["Ouvert", "Split"])
        #expect(spaces[0].tabManager.selectedTab == nil)
        #expect(summary.tabs == 6)
    }

    @Test func `profiles added in Arc become profiles, with their favorites`() {
        let profilesBefore = session.profiles.count
        let (_, spaces) = importer().importSidebar(sidebar, options: ArcImportOptions())
        #expect(session.profiles.count == profilesBefore + 1)
        let travail = spaces[1]
        #expect(travail.record.profile?.name == "Profile 1")
        #expect(travail.tabManager.favoriteTabs.map(\.title) == ["Intranet"])
    }

    @Test func `favorites join the displayed profile once, shared by its Spaces`() throws {
        let displayed = try #require(session.spaces.first)
        let (_, spaces) = importer().importSidebar(sidebar, options: ArcImportOptions())
        #expect(displayed.tabManager.favoriteTabs.map(\.title) == ["Mail", "Agenda"])
        // Les Spaces importés du même profil partagent les mêmes onglets.
        #expect(spaces[0].tabManager.favoriteTabs.map(\.id) == displayed.tabManager.favoriteTabs.map(\.id))

        // Un second import n'ajoute pas les adresses déjà en favori, et reprend le profil de même nom.
        let profiles = session.profiles.count
        let (summary, again) = importer().importSidebar(sidebar, options: ArcImportOptions())
        #expect(displayed.tabManager.favoriteTabs.count == 2)
        #expect(summary.favorites == 0)
        #expect(summary.profiles == 0)
        #expect(session.profiles.count == profiles)
        #expect(again[1].record.profile === spaces[1].record.profile)
        #expect(again[1].tabManager.favoriteTabs.map(\.title) == ["Intranet"])
    }

    @Test func `the default Arc profile goes to the chosen profile`() throws {
        let other = session.addProfile(named: "Autre")
        let profile = try #require(other.record.profile)
        let (_, spaces) = importer().importSidebar(sidebar, options: ArcImportOptions(profileID: profile.id))
        #expect(spaces[0].record.profile === profile)
        #expect(spaces[2].record.profile === profile)
        // Les favoris rejoignent ce profil, dont un Space n'est pas affiché : le premier les tient.
        #expect(other.tabManager.favoriteTabs.map(\.title) == ["Mail", "Agenda"])
    }
}
