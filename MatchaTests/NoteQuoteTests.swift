import Foundation
@testable import Matcha
import SwiftData
import Testing

/// “Add to Note” (task 12.6): the passage cleaned, the link back to it (text fragment), the blocks added to the note,
/// the item's place in the menu, and the page's note made or completed.
@MainActor
struct NoteQuoteTests {
    private func url(_ address: String) throws -> URL {
        try #require(URL(string: address))
    }

    @Test func `a passage keeps its lines, not its extra spaces`() {
        #expect(NoteQuote.cleaned("  Hello \t world \n\n  second   line ") == "Hello world\nsecond line")
        #expect(NoteQuote.cleaned(" \n ").isEmpty)
        #expect(NoteQuote.cleaned(String(repeating: "a", count: NoteQuote.maximumLength + 10)).count == NoteQuote.maximumLength)
    }

    @Test func `the link goes back to the passage`() throws {
        let page = try url("https://example.com/guide?x=1#intro")
        let short = try #require(NoteQuote.fragmentURL(for: "Hello, big-world & co", in: page))
        #expect(short.absoluteString == "https://example.com/guide?x=1#:~:text=Hello%2C%20big%2Dworld%20%26%20co")

        let words = (1 ... 80).map { "word\($0)" }.joined(separator: " ")
        let long = try #require(NoteQuote.fragmentURL(for: words, in: page))
        #expect(long.absoluteString.hasSuffix("#:~:text=word1%20word2%20word3%20word4,word77%20word78%20word79%20word80"))
        #expect(NoteQuote.fragmentURL(for: "  ", in: page) == nil)
    }

    @Test func `the quote and its link are added at the end of the note`() throws {
        let content = "[{\"id\": \"p\", \"type\": \"paragraph\", \"props\": {}, \"content\": []}]"
        let source = try url("https://example.com/#:~:text=Hi")
        let updated = try #require(NoteQuote.appending("First line\nSecond", source: source, sourceTitle: "Example", to: content))
        let blocks = try #require(JSONSerialization.jsonObject(with: Data(updated.utf8)) as? [[String: Any]])
        #expect(blocks.map { $0["type"] as? String } == ["paragraph", "blockquote", "paragraph"])
        let quote = try #require(blocks[1]["content"] as? [[String: Any]])
        #expect(quote.map { $0["type"] as? String } == ["text", "hardBreak", "text"])
        #expect(quote.last?["text"] as? String == "Second")
        let link = try #require((blocks[2]["content"] as? [[String: Any]])?.first)
        #expect(link["href"] as? String == "https://example.com/#:~:text=Hi")
        #expect(NotePlainText.text(of: updated) == "First line\nSecond\nExample")

        #expect(NoteQuote.appending("Text", source: nil, sourceTitle: "", to: "{\"not\": \"blocks\"}") == nil)
        #expect(NoteQuote.appending("  ", source: nil, sourceTitle: "", to: "[]") == nil)
    }

    @Test func `the item follows Copy in the menu of a selection`() {
        let selection = ["WKMenuItemIdentifierLookUp", nil, "WKMenuItemIdentifierCopy", "WKMenuItemIdentifierShareMenu"]
        #expect(PageMenuPlan.noteQuoteIndex(for: selection) == 3)
        #expect(PageMenuPlan.noteQuoteIndex(for: ["WKMenuItemIdentifierReload"]) == nil)
    }
}

/// The page's note receives the passage (task 12.6).
@MainActor
@Suite(.webKit)
struct NoteQuotePanelTests {
    private let container: ModelContainer
    private let store: NoteStore
    private let panel: NotesPanelModel

    init() throws {
        container = try BrowserSchema.makeContainer(inMemory: true)
        store = NoteStore(context: container.mainContext)
        panel = NotesPanelModel(store: store)
    }

    @Test func `a passage makes the page's note, then completes it`() async throws {
        let page = try #require(URL(string: "https://example.com/article"))
        await panel.quote("First passage", from: page, title: "Article")
        let note = try #require(store.notes.first)
        #expect(note.title == "Article")
        #expect(note.link?.scope == .page)
        #expect(panel.isOpen)
        #expect(store.record(note.id)?.plainText == "First passage\nArticle")

        await panel.quote("Second passage", from: page, title: "Article")
        #expect(store.notes.count == 1)
        #expect(store.record(note.id)?.plainText == "First passage\nArticle\nSecond passage\nArticle")
    }

    @Test func `a site's note takes the passage when the page has none`() async throws {
        let page = try #require(URL(string: "https://docs.example.com/a"))
        let site = try #require(NoteLink(url: page, scope: .site, title: nil))
        let note = try #require(store.createNote(profileID: nil, title: "Site", link: site))
        await panel.quote("Passage", from: page, title: nil)
        #expect(store.notes.count == 1)
        #expect(store.record(note.id)?.plainText == "Passage\ndocs.example.com")
    }

    @Test func `no passage is kept in a private window`() async throws {
        let privatePanel = NotesPanelModel(store: NoteStore(context: nil))
        #expect(!privatePanel.acceptsQuotes)
        try await privatePanel.quote("Passage", from: #require(URL(string: "https://example.com")), title: nil)
        #expect(!privatePanel.isOpen)
    }
}
