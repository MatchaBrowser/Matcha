import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Import of an Arc sidebar into an in-memory session (task 7.1): Spaces, folders, pinned tabs, open tabs,
/// profiles, favorites.
@MainActor
@Suite(.webKit)
struct ArcImporterTests {
    private let session: BrowserSession
    private let sidebar: ArcSidebar

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let url = try #require(Bundle(for: TestPages.self).url(forResource: "arc-sidebar-sample.json", withExtension: nil))
        sidebar = try ArcSidebarParser.parse(Data(contentsOf: url))
    }

    private func importer() -> ArcImporter {
        var importer = ArcImporter(session: session)
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
        #expect(Set(pinned.compactMap(\.pinnedTitle)) == ["Page A", "Page B", "example.com"])
        #expect(pinned.compactMap(\.customTitle) == ["Renommé"])
        let folders = perso.record.folders ?? []
        let outer = try #require(folders.first { $0.name == "Dossier" })
        let inner = try #require(folders.first { $0.name == "Sous-dossier" })
        #expect(outer.parent == nil)
        #expect(inner.parent === outer)
        #expect(pinned.first { $0.customTitle == "Renommé" }?.folder === outer)
        #expect(pinned.first { $0.pinnedTitle == "example.com" }?.folder === inner)
        // The open Space got its saved content back, the name given in Arc included.
        #expect(perso.tabManager.tabs.contains { $0.displayTitle == "Renommé" && $0.pageTitle == "Page B" })
        #expect(perso.tabManager.tabs.count(where: { $0.pinnedURL != nil && $0.pinnedTitle != "Mail" && $0.pinnedTitle != "Agenda" }) == 3)
        // Nothing loads by itself: no imported tab is selected.
        #expect(perso.tabManager.selectedTab == nil)
        // Open tabs: not by default.
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
        // An imported Space of the same profile shows the same tabs once displayed.
        session.showFavorites(in: spaces[0])
        #expect(spaces[0].tabManager.favoriteTabs.map(\.id) == displayed.tabManager.favoriteTabs.map(\.id))

        // A second import does not add the addresses already in favorites, and reuses the profile with the same name.
        let profiles = session.profiles.count
        let (summary, again) = importer().importSidebar(sidebar, options: ArcImportOptions())
        #expect(displayed.tabManager.favoriteTabs.count == 2)
        #expect(summary.favorites == 0)
        #expect(summary.profiles == 0)
        #expect(session.profiles.count == profiles)
        #expect(again[1].record.profile === spaces[1].record.profile)
        #expect(again[1].tabManager.favoriteTabs.map(\.title) == ["Intranet"])
    }

    /// Review SV8: the favorites of a profile without an open Space are saved, after its own, without duplicates.
    @Test func `favorites of a profile without an open Space are kept`() throws {
        let context = session.container.mainContext
        let profile = ProfileRecord(name: "Sans Space", order: 9)
        context.insert(profile)
        let existing = TabRecord(url: URL(string: "https://mail.example/"), title: "Courrier", place: .favorite)
        context.insert(existing)
        existing.pinnedURL = existing.url
        existing.profile = profile
        session.save(context)
        session.refreshProfiles()
        let favorites = try [
            ImportedTab(title: "Mail", url: #require(URL(string: "https://mail.example/"))),
            ImportedTab(title: "Agenda", url: #require(URL(string: "https://agenda.example/"))),
        ]
        let arc = ArcSidebar(spaces: [], favorites: [.default: favorites], skippedItems: 0)
        let (summary, _) = importer().importSidebar(arc, options: ArcImportOptions(profileID: profile.id))
        #expect(summary.favorites == 1)
        let space = session.addSpace(in: profile)
        #expect(space.tabManager.favoriteTabs.map(\.title) == ["Courrier", "Agenda"])
    }

    @Test func `the default Arc profile goes to the chosen profile`() throws {
        let other = session.addProfile(named: "Autre")
        let profile = try #require(other.record.profile)
        let (_, spaces) = importer().importSidebar(sidebar, options: ArcImportOptions(profileID: profile.id))
        #expect(spaces[0].record.profile === profile)
        #expect(spaces[2].record.profile === profile)
        // The favorites join this profile, one of whose Spaces is not shown: the first one holds them.
        #expect(other.tabManager.favoriteTabs.map(\.title) == ["Mail", "Agenda"])
    }
}
