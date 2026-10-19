import Foundation
@testable import Matcha
import Testing

/// Manifest of the blocking lists (task 6.2): reading, invalid or duplicate entries ignored, unknown format.
struct BlocklistManifestTests {
    private func manifest(_ json: String) throws -> BlocklistManifest {
        try BlocklistManifest(data: Data(json.utf8))
    }

    private static let easyList = """
    { "identifier" : "easylist", "name" : "EasyList", "version" : "2026.10.18", "file" : "blocklist-easylist.json",
        "license" : "CC BY-SA 3.0", "homepage" : "https://easylist.to" }
    """

    @Test func `reads the lists in order with their credits`() throws {
        let privacy = #"{ "identifier" : "easyprivacy", "name" : "EasyPrivacy", "version" : "7", "file" : "blocklist-easyprivacy.json" }"#
        let result = try manifest(#"{ "format" : 1, "lists" : [ \#(Self.easyList), \#(privacy) ] }"#)
        #expect(result.lists.map(\.identifier) == ["easylist", "easyprivacy"])
        let first = try #require(result.lists.first)
        #expect(first == BlocklistEntry(
            identifier: "easylist",
            name: "EasyList",
            version: "2026.10.18",
            file: "blocklist-easylist.json",
            license: "CC BY-SA 3.0",
            homepage: "https://easylist.to",
        ))
        #expect(first.homepageURL == URL(string: "https://easylist.to"))
        #expect(result.lists.last?.license == nil)
        #expect(result.lists.last?.homepageURL == nil)
    }

    @Test func `an empty manifest has no list`() throws {
        #expect(try manifest(#"{ "format" : 1, "lists" : [] }"#).lists.isEmpty)
    }

    /// The manifest shipped with the app (empty until task 6.1 has added a list) can be read.
    @Test func `the bundled manifest is readable`() async throws {
        let bundled = try await BlocklistBundle(bundle: .main).manifest()
        #expect(bundled != nil)
    }

    @Test func `a newer format is refused`() {
        #expect(throws: BlocklistManifest.Error.unsupportedFormat(2)) {
            try manifest(#"{ "format" : 2, "lists" : [ \#(Self.easyList) ] }"#)
        }
    }

    @Test func `unreadable json is refused`() {
        #expect(throws: (any Error).self) {
            try manifest(#"{ "lists" : [] }"#)
        }
        #expect(throws: (any Error).self) {
            try manifest("[")
        }
    }

    @Test(arguments: [
        #"{ "name" : "Sans identifiant", "version" : "1", "file" : "a.json" }"#,
        #"{ "identifier" : "EasyList", "name" : "Majuscules", "version" : "1", "file" : "a.json" }"#,
        #"{ "identifier" : "easy list", "name" : "Espace", "version" : "1", "file" : "a.json" }"#,
        #"{ "identifier" : "-easylist", "name" : "Tiret d'abord", "version" : "1", "file" : "a.json" }"#,
        #"{ "identifier" : "easylist", "name" : "  ", "version" : "1", "file" : "a.json" }"#,
        #"{ "identifier" : "easylist", "name" : "Sans version", "version" : "", "file" : "a.json" }"#,
        #"{ "identifier" : "easylist", "name" : "Version / barre", "version" : "1/2", "file" : "a.json" }"#,
        #"{ "identifier" : "easylist", "name" : "Dossier", "version" : "1", "file" : "Blocklists/a.json" }"#,
        #"{ "identifier" : "easylist", "name" : "Pas du JSON", "version" : "1", "file" : "a.txt" }"#,
        #"{ "identifier" : "easylist", "name" : "Nom vide", "version" : "1", "file" : ".json" }"#,
        #"{ "identifier" : "easylist", "name" : "Version nombre", "version" : 1, "file" : "a.json" }"#,
    ])
    func `an invalid entry is ignored, not the others`(entry: String) throws {
        let result = try manifest(#"{ "format" : 1, "lists" : [ \#(entry), \#(Self.easyList) ] }"#)
        #expect(result.lists.map(\.name) == ["EasyList"])
    }

    @Test func `a duplicate identifier keeps the first list`() throws {
        let duplicate = #"{ "identifier" : "easylist", "name" : "Autre", "version" : "2", "file" : "autre.json" }"#
        let result = try manifest(#"{ "format" : 1, "lists" : [ \#(Self.easyList), \#(duplicate) ] }"#)
        #expect(result.lists.map(\.name) == ["EasyList"])
    }

    @Test(arguments: ["http://easylist.to", "easylist.to", "javascript:alert(1)", ""])
    func `only an https homepage is shown`(homepage: String) {
        let entry = BlocklistEntry(identifier: "a", name: "A", version: "1", file: "a.json", homepage: homepage)
        #expect(entry.homepageURL == nil)
    }
}
