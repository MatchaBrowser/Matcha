import Foundation
@testable import Matcha
import Testing

struct CommandPrimaryRowsTests {
    private func rows(_ text: String, engine: SearchEngine = .google) -> [CommandRow] {
        CommandPrimaryRows.make(for: query(text, engine: engine))
    }

    @Test func `empty text gives no row`() {
        #expect(rows("").isEmpty)
        #expect(rows("  \n").isEmpty)
    }

    @Test func `address gives an open row with the resolved url`() throws {
        let row = try #require(rows("apple.com").first)
        let url = try #require(URL(string: "https://apple.com"))
        #expect(row.id == CommandPrimaryRows.id)
        #expect(row.style == .openAddress)
        #expect(row.title == "apple.com")
        #expect(row.subtitle == "https://apple.com")
        #expect(row.url == url)
        #expect(row.target == .open(url))
    }

    @Test func `bare domain adds a search row`() throws {
        let found = rows("apple.com")
        #expect(found.count == 2)
        let search = found[1]
        let url = try #require(URL(string: "https://www.google.com/search?q=apple.com"))
        #expect(search.id == CommandPrimaryRows.searchAlternativeID)
        #expect(search.id == "primary.search")
        #expect(search.style == .searchAlternative)
        #expect(search.title == "apple.com")
        #expect(search.target == .open(url))
        #expect(try rows("node.js", engine: .duckDuckGo).last?.target == .open(#require(URL(string: "https://duckduckgo.com/?q=node.js"))))
    }

    @Test(arguments: ["localhost:3000", "192.168.1.1", "apple.com/fr", "https://apple.com", "apple.com:8443", "about:blank"])
    func `no search row for ports paths ip and schemes`(text: String) {
        let found = rows(text)
        #expect(found.count == 1)
        #expect(found.first?.style == .openAddress)
    }

    @Test func `text gives a search row for the exact trimmed text`() throws {
        let row = try #require(rows("  swift 6.4 ").first)
        let url = try #require(URL(string: "https://www.google.com/search?q=swift%206.4"))
        #expect(rows("  swift 6.4 ").count == 1)
        #expect(row.id == CommandPrimaryRows.id)
        #expect(row.style == .search)
        #expect(row.title == "swift 6.4")
        #expect(row.subtitle == nil)
        #expect(row.target == .open(url))
    }

    @Test func `local host subtitle shows http`() {
        let row = rows("localhost:3000").first
        #expect(row?.subtitle == "http://localhost:3000")
        #expect(rows("https://apple.com").first?.subtitle == nil)
    }

    @Test func `current address row keeps the url as is`() throws {
        let url = try #require(URL(string: "about:blank?one"))
        let row = CommandPrimaryRows.current(url)
        #expect(row.id == CommandPrimaryRows.id)
        #expect(row.style == .openAddress)
        #expect(row.title == "about:blank?one")
        #expect(row.subtitle == nil)
        #expect(row.target == .open(url))
    }
}
