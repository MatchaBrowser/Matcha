import Foundation
@testable import Matcha
import Testing
import WebKit

/// Translation of a real page (task 9.2): the script in its isolated world cuts the page into blocks, the app has them
/// translated (upper-cased by `FakeTextTranslator`), the script writes them, follows the page's changes and puts the
/// original back. Pages served by `TestPages`, without network.
@MainActor
@Suite(.webKit)
struct PageTranslationIntegrationTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    private static let article = """
    <h1 id="title">Hello world</h1>
    <p id="link">Click <a href="https://example.com/">this link</a> to read <code>fetchData()</code>.</p>
    <pre id="code">let greeting = "hello"</pre>
    <p id="brand" translate="no">Matcha Browser</p>
    <p id="note" class="notranslate">Keep me</p>
    <p id="lines">Line one<br>Line two</p>
    <div id="hidden" style="display: none">Hidden text</div>
    <div style="display: contents"><p id="contents">Inside contents</p></div>
    <textarea id="field">typed text</textarea>
    """

    /// Selected tab once the page `name` with `body` is loaded.
    private func open(_ name: String, body: String) async throws -> BrowserTab {
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url(name, body: body))
        try await waitUntil { tab.title == name && !tab.isLoading }
        return tab
    }

    private func evaluate(_ script: String, in tab: BrowserTab) async throws -> Any? {
        try await tab.loadedWebView.callAsyncJavaScript(script, contentWorld: .page)
    }

    private func html(of id: String, in tab: BrowserTab) async throws -> String? {
        try await evaluate("return document.getElementById('\(id)').innerHTML", in: tab) as? String
    }

    private func text(of id: String, in tab: BrowserTab) async throws -> String? {
        try await evaluate("return document.getElementById('\(id)').textContent", in: tab) as? String
    }

    /// Translates with the fake translator; `steps` records the number of blocks of each step.
    private func translate(_ tab: BrowserTab, method: TranslationMethod = .plainText, steps: StepRecorder? = nil) {
        tab.translation.translate(in: tab.loadedWebView) { blocks in
            steps?.counts.append(blocks.count)
            return try await PageBlockTranslator(translator: FakeTextTranslator(), method: method).translate(blocks)
        }
    }

    @Test func `the page is translated, links and code in place, and put back`() async throws {
        let tab = try await open("article", body: Self.article)
        translate(tab)
        try await waitUntil { tab.translation.state == .translated }

        #expect(try await text(of: "title", in: tab) == "HELLO WORLD")
        #expect(try await html(of: "link", in: tab) ==
            #"CLICK <a href="https://example.com/">THIS LINK</a> TO READ <code>fetchData()</code>."#)
        #expect(try await html(of: "lines", in: tab) == "LINE ONE<br>LINE TWO")
        #expect(try await text(of: "contents", in: tab) == "INSIDE CONTENTS")
        // Left as they are: code block, `translate="no"`, `.notranslate`, hidden text, text the user types.
        #expect(try await text(of: "code", in: tab) == #"let greeting = "hello""#)
        #expect(try await text(of: "brand", in: tab) == "Matcha Browser")
        #expect(try await text(of: "note", in: tab) == "Keep me")
        #expect(try await text(of: "hidden", in: tab) == "Hidden text")
        #expect(try await evaluate("return document.getElementById('field').value", in: tab) as? String == "typed text")

        await tab.translation.showOriginal()
        #expect(tab.translation.state == .original)
        #expect(try await text(of: "title", in: tab) == "Hello world")
        #expect(try await html(of: "link", in: tab) ==
            #"Click <a href="https://example.com/">this link</a> to read <code>fetchData()</code>."#)
        #expect(try await html(of: "lines", in: tab) == "Line one<br>Line two")
    }

    @available(macOS 26.4, *)
    @Test func `the rich-text method writes each piece in its element`() async throws {
        let tab = try await open("rich", body: Self.article)
        translate(tab, method: .richText)
        try await waitUntil { tab.translation.state == .translated }
        #expect(try await html(of: "link", in: tab) ==
            #"CLICK <a href="https://example.com/">THIS LINK</a> TO READ <code>fetchData()</code>."#)
    }

    @Test func `text the page adds or changes afterwards is translated too`() async throws {
        let tab = try await open("dynamic", body: Self.article)
        translate(tab)
        try await waitUntil { tab.translation.state == .translated }

        _ = try await evaluate("document.body.insertAdjacentHTML('beforeend', '<p id=\"late\">New paragraph</p>')", in: tab)
        try await waitUntilAsync { try await text(of: "late", in: tab) == "NEW PARAGRAPH" }

        // The page writes into a translated node: its text is the new original, translated in turn.
        _ = try await evaluate("document.getElementById('title').firstChild.data = 'Goodbye'", in: tab)
        try await waitUntilAsync { try await text(of: "title", in: tab) == "GOODBYE" }

        await tab.translation.showOriginal()
        #expect(try await text(of: "title", in: tab) == "Goodbye")
        #expect(try await text(of: "late", in: tab) == "New paragraph")
        // Back in its language, the page is no longer followed.
        _ = try await evaluate("document.body.insertAdjacentHTML('beforeend', '<p id=\"after\">Not followed</p>')", in: tab)
        try await Task.sleep(for: .seconds(1))
        #expect(try await text(of: "after", in: tab) == "Not followed")
    }

    @Test func `a long page is translated in steps`() async throws {
        let paragraphs = (0 ..< 450).map { "<p id=\"p\($0)\">Paragraph \($0)</p>" }.joined()
        let tab = try await open("long", body: paragraphs)
        let steps = StepRecorder()
        translate(tab, steps: steps)
        // The page counts as translated from its first step on: the last paragraph comes with the last step.
        try await waitUntilAsync { try await text(of: "p449", in: tab) == "PARAGRAPH 449" }
        #expect(tab.translation.state == .translated)
        #expect(steps.counts == Array(repeating: TranslationLimits.maximumBlocksPerCollect, count: 9))
    }

    @Test func `translating again starts from the original text`() async throws {
        let tab = try await open("again", body: Self.article)
        translate(tab)
        try await waitUntil { tab.translation.state == .translated }
        tab.translation.translate(in: tab.loadedWebView) { blocks in
            Dictionary(uniqueKeysWithValues: blocks.map { block in (block.id, block.pieces.map { "«\($0.text)»" }) })
        }
        try await waitUntil { tab.translation.state == .translated }
        #expect(try await text(of: "title", in: tab) == "«Hello world»")
    }

    @Test func `a new document is in its own language`() async throws {
        let tab = try await open("first", body: Self.article)
        translate(tab)
        try await waitUntil { tab.translation.state == .translated }
        tab.load(TestPages.url("second", body: "<p id='other'>Other page</p>"))
        try await waitUntil { tab.title == "second" && !tab.isLoading }
        #expect(tab.translation.state == .original)
        #expect(try await text(of: "other", in: tab) == "Other page")
    }

    @Test func `the language of a loaded page is read and its translation offered`() async throws {
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        let german = "Der schnelle braune Fuchs springt über den faulen Hund, während die Kinder im Garten spielen."
        let url = try #require(URL(string: "https://example.com/allemand"))
        tab.loadedWebView.loadSimulatedRequest(
            URLRequest(url: url),
            responseHTML: "<html lang='en'><title>allemand</title><p>\(german)</p>",
        )
        try await waitUntil { tab.translation.pageLanguage != nil }
        #expect(tab.translation.pageLanguage?.languageCode == "de")
        #expect(PageTranslationActions.canTranslate(tab))
        // Offered whatever the target: the popover can choose another one.
        #expect(TranslateButton.isShown(for: tab))
        #expect(try TranslationLanguages(preferred: ["fr-FR"]).canTranslate(from: #require(tab.translation.pageLanguage)))
        #expect(try !TranslationLanguages(preferred: ["de-CH"]).canTranslate(from: #require(tab.translation.pageLanguage)))

        // A new document: its language isn't known until it has loaded.
        let other = try #require(URL(string: "https://example.com/vide"))
        tab.loadedWebView.loadSimulatedRequest(URLRequest(url: other), responseHTML: "<title>vide</title>")
        try await waitUntil { tab.title == "vide" && !tab.isLoading }
        #expect(tab.translation.pageLanguage == nil)
        #expect(TranslateButton.isShown(for: tab))
    }

    @Test func `pages of the app can't be translated`() async throws {
        let tab = try await open("interne", body: Self.article)
        // `obtest:` here, like the app's own pages: only web pages and local files are translated.
        #expect(!PageTranslationActions.canTranslate(tab))
        #expect(!TranslateButton.isShown(for: tab))
        #expect(tab.translation.pageLanguage == nil)
    }

    @Test func `a failure of the translator is reported`() async throws {
        let tab = try await open("failure", body: Self.article)
        tab.translation.translate(in: tab.loadedWebView) { blocks in
            try await PageBlockTranslator(translator: FakeTextTranslator(fails: true), method: .plainText).translate(blocks)
        }
        try await waitUntil { tab.translation.state == .failed(.other) }
        #expect(try await text(of: "title", in: tab) == "Hello world")
    }
}

/// Number of blocks of each step of a translation.
@MainActor
final class StepRecorder {
    var counts: [Int] = []
}
