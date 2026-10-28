import Foundation
@testable import Matcha
import Testing

/// Reading of the Arc sidebar (task 7.1), on a made-up sample (`Fixtures/arc-sidebar-sample.json`) that follows the
/// structure of Arc's file: icon and emoji, solid color and gradient, added profile, nested folders, note, split
/// view, internal address, duplicate favorites.
@MainActor
@Suite(.webKit)
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

    /// The title of an item is the name the user gave the tab in Arc; `savedTitle`, the page's.
    @Test func `pinned items keep their folders, titles, names and order`() throws {
        let pinned = try sample().spaces[0].pinned
        #expect(try pinned == [
            .tab(ImportedTab(title: "Page A", url: url("https://example.com/a"))),
            .folder(name: "Dossier", children: [
                .tab(ImportedTab(title: "Page B", url: url("https://example.com/b"), customTitle: "Renommé")),
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
        // The Arc note and the `arc://` address.
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

    /// Review TS12: the import reads the file off the main thread, and never one larger than any Arc sidebar.
    @Test func `the import reads the file, never one past the limit`() async throws {
        let sample = try #require(Bundle(for: TestPages.self).url(forResource: "arc-sidebar-sample.json", withExtension: nil))
        #expect(try await ArcImportModel.read(sample).spaces.count == self.sample().spaces.count)

        let large = FileManager.default.temporaryDirectory.appending(path: "ArcSidebarParserTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: large) }
        try Data(contentsOf: sample).write(to: large)
        let handle = try FileHandle(forWritingTo: large)
        // Sparse: past the limit without writing it.
        try handle.truncate(atOffset: UInt64(ArcImportModel.maximumFileSize + 1))
        try handle.close()
        await #expect(throws: ArcSidebarParser.Failure.tooLarge) { try await ArcImportModel.read(large) }
    }

    @Test func `odd shapes are tolerated`() throws {
        // Pairs replaced by objects carrying their `id`, containers as objects, item without an address.
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
        // Without `savedTitle`, the page's title is the host; Arc's title stays the tab's name.
        #expect(try sidebar.spaces[0].pinned == [.tab(ImportedTab(
            title: "example.org",
            url: url("https://example.org/"),
            customTitle: "Titre",
        ))])
        #expect(sidebar.spaces[0].openTabs.isEmpty)
        #expect(sidebar.favorites.isEmpty)
        #expect(sidebar.skippedItems == 1)
    }

    /// Sidebar of one Space whose pinned container holds `items` (identifier, object), the container itself first.
    private func sidebar(pinned children: [String], items: [(String, [String: Any])]) throws -> ArcSidebar {
        var pairs: [Any] = ["P", ["childrenIds": children, "data": ["itemContainer": [:]]]]
        for (id, item) in items {
            pairs += [id, item]
        }
        let root: [String: Any] = ["sidebar": ["containers": [[
            "items": pairs,
            "spaces": ["S", ["title": "Seul", "containerIDs": ["pinned", "P"]]],
        ]]]]
        return try ArcSidebarParser.parse(JSONSerialization.data(withJSONObject: root))
    }

    @Test func `a forged file can't nest folders without end`() throws {
        // 200 folders, each inside the previous one, and a tab at the bottom (audit E7).
        let items = (0 ..< 200).map { level -> (String, [String: Any]) in
            let children = level < 199 ? ["F\(level + 1)"] : ["T"]
            return ("F\(level)", ["title": "Niveau \(level)", "childrenIds": children, "data": ["list": [:]]])
        } + [("T", ["childrenIds": [], "data": ["tab": ["savedURL": "https://example.com/"]]])]
        let pinned = try sidebar(pinned: ["F0"], items: items).spaces[0].pinned
        let folders = ImportNode.folderCount(of: pinned)
        #expect(folders > 0 && folders <= ArcSidebarParser.maximumDepth)
        #expect(ImportNode.tabCount(of: pinned) == 0)
    }

    @Test func `a forged file can't hold more items than the limit`() throws {
        let count = ArcSidebarParser.maximumItems + 1
        let ids = (0 ..< count).map { "T\($0)" }
        let items = ids.map { ($0, ["childrenIds": [], "data": ["tab": ["savedURL": "https://example.com/\($0)"]]] as [String: Any]) }
        let sidebar = try sidebar(pinned: ids, items: items)
        #expect(ImportNode.tabCount(of: sidebar.spaces[0].pinned) == ArcSidebarParser.maximumItems)
        // Review SV9: told apart from the Arc notes and pages.
        #expect(sidebar.itemsBeyondLimit == 1)
        #expect(sidebar.skippedItems == 0)
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
