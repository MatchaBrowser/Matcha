import Foundation
@testable import Matcha
import Testing

/// Lecture de la barre d'Arc (tâche 7.1), sur un exemple inventé (`Fixtures/arc-sidebar-sample.json`) qui reprend la
/// structure du fichier d'Arc : icône et emoji, couleur unie et dégradé, profil ajouté, dossiers imbriqués, note,
/// split view, adresse interne, favoris en double.
@MainActor
struct ArcSidebarParserTests {
    private func sample() throws -> ArcSidebar {
        let url = try #require(Bundle(for: TestPages.self).url(forResource: "arc-sidebar-sample.json", withExtension: nil))
        return try ArcSidebarParser.parse(Data(contentsOf: url))
    }

    private func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    @Test func `spaces keep their order, name, icon, colors and profile`() throws {
        let sidebar = try sample()
        #expect(sidebar.spaces.map(\.name) == ["Perso", "Travail", ""])
        #expect(sidebar.spaces.map(\.icon) == [.named("star"), .emoji("🍵"), nil])
        #expect(sidebar.spaces[0].colors == [ThemeColor(red: 0.4, green: 0.5, blue: 0.6)])
        #expect(sidebar.spaces[1].colors == [ThemeColor(red: 1, green: 0, blue: 0), ThemeColor(red: 0, green: 0, blue: 1)])
        #expect(sidebar.spaces[2].colors.isEmpty)
        #expect(sidebar.spaces.map(\.profile) == [.default, .custom("Profile 1"), .default])
        #expect(sidebar.customProfiles == ["Profile 1"])
    }

    @Test func `pinned items keep their folders, titles and order`() throws {
        let pinned = try sample().spaces[0].pinned
        #expect(try pinned == [
            .tab(ImportedTab(title: "Page A", url: url("https://example.com/a"))),
            .folder(name: "Dossier", children: [
                .tab(ImportedTab(title: "Renommé", url: url("https://example.com/b"))),
                .folder(name: "Sous-dossier", children: [
                    .tab(ImportedTab(title: "example.com", url: url("https://example.com/c"))),
                ]),
            ]),
        ])
        #expect(ImportNode.tabCount(of: pinned) == 3)
        #expect(ImportNode.folderCount(of: pinned) == 2)
    }

    @Test func `open tabs flatten split views and drop internal addresses`() throws {
        let sidebar = try sample()
        #expect(try sidebar.spaces[0].openTabs == [
            .tab(ImportedTab(title: "Ouvert", url: url("https://example.com/open"))),
            .tab(ImportedTab(title: "Split", url: url("https://example.com/split"))),
        ])
        // La note d'Arc et l'adresse `arc://`.
        #expect(sidebar.skippedItems == 2)
    }

    @Test func `favorites are read per profile`() throws {
        let sidebar = try sample()
        #expect(sidebar.favorites[.default]?.map(\.title) == ["Mail", "Mail (doublon)", "Agenda"])
        #expect(sidebar.favorites[.custom("Profile 1")]?.map(\.title) == ["Intranet"])
        #expect(sidebar.favoriteCount == 4)
        #expect(ArcImporter.withoutDuplicates(sidebar.favorites[.default] ?? []).map(\.title) == ["Mail", "Agenda"])
    }

    @Test func `files that are not an Arc sidebar are refused`() {
        #expect(throws: ArcSidebarParser.Failure.unreadable) { try ArcSidebarParser.parse(Data("pas du JSON".utf8)) }
        #expect(throws: ArcSidebarParser.Failure.notArcSidebar) { try ArcSidebarParser.parse(Data(#"{"version": 1}"#.utf8)) }
        let noSpaces = #"{"sidebar": {"containers": [{"global": {}}, {"items": []}]}}"#
        #expect(throws: ArcSidebarParser.Failure.notArcSidebar) { try ArcSidebarParser.parse(Data(noSpaces.utf8)) }
    }

    @Test func `odd shapes are tolerated`() throws {
        // Paires remplacées par des objets portant leur `id`, conteneurs en objets, élément sans adresse.
        let json = """
        {"sidebar": {"containers": [{"items": [
            {"id": "P", "childrenIds": ["T", "X", "missing"], "data": {"itemContainer": {}}},
            {"id": "T", "title": "Titre", "childrenIds": [], "data": {"tab": {"savedURL": "https://example.org/"}}},
            {"id": "X", "childrenIds": [], "data": {"tab": {"savedURL": ""}}}
        ], "spaces": [
            {"id": "S", "title": "Seul", "containerIDs": [{"pinned": {}}, "P"]}
        ]}]}}
        """
        let sidebar = try ArcSidebarParser.parse(Data(json.utf8))
        #expect(sidebar.spaces.count == 1)
        #expect(try sidebar.spaces[0].pinned == [.tab(ImportedTab(title: "Titre", url: url("https://example.org/")))])
        #expect(sidebar.spaces[0].openTabs.isEmpty)
        #expect(sidebar.favorites.isEmpty)
        #expect(sidebar.skippedItems == 1)
    }

    @Test func `arc icons and colors become a Matcha icon and theme`() {
        let available: Set = ["star", "star.fill", "server.rack", "bolt"]
        let exists: (String) -> Bool = { available.contains($0) }
        #expect(ArcAppearance.spaceSymbol(for: .named("star"), symbolExists: exists) == "star.fill")
        #expect(ArcAppearance.spaceSymbol(for: .named("server"), symbolExists: exists) == "server.rack")
        #expect(ArcAppearance.spaceSymbol(for: .named("bolt"), symbolExists: exists) == "bolt")
        #expect(ArcAppearance.spaceSymbol(for: .named("skull"), symbolExists: exists) == "emoji:💀")
        #expect(ArcAppearance.spaceSymbol(for: .named("unknown"), symbolExists: exists) == nil)
        #expect(ArcAppearance.spaceSymbol(for: .emoji("🍵"), symbolExists: exists) == "emoji:🍵")
        #expect(ArcAppearance.spaceSymbol(for: nil, symbolExists: exists) == nil)

        let color = ThemeColor(red: 0.4, green: 0.5, blue: 0.6)
        #expect(ArcAppearance.theme(for: []) == nil)
        #expect(ArcAppearance.theme(for: [color])?.colors == [color, color.mixed(with: .black, amount: 0.35)])
        let four = [color, .white, .black, color]
        #expect(ArcAppearance.theme(for: four)?.colors == [color, .white, .black])
    }
}
