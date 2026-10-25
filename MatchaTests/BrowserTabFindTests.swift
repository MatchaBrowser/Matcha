import Foundation
@testable import Matcha
import Testing
import WebKit

/// Search in a real page (task 5.3): what `WKWebView.find(_:configuration:)` does behind
/// `BrowserTab.search`, and the tab's search (deselection, page unloaded or changed).
@MainActor
@Suite(.webKit)
struct BrowserTabFindTests {
    /// Tab on a local page whose body is `body`.
    private func page(_ body: String) async throws -> BrowserTab {
        let tab = BrowserTab(configuration: TestPages.configuration())
        tab.load(TestPages.url("find", body: body))
        try await waitUntil { tab.title == "find" && !tab.isLoading }
        return tab
    }

    /// Text selected in the page and its offset in its node.
    private func selection(in tab: BrowserTab) async throws -> String {
        let script = "(() => { const s = window.getSelection(); return s.rangeCount ? String(s) + '@' + s.anchorOffset : '' })()"
        let value = try await tab.loadedWebView.evaluateJavaScript(script, contentWorld: .defaultClient)
        return value as? String ?? ""
    }

    @Test func `search selects the match, ignores case and wraps around`() async throws {
        let tab = try await page("<p>Postfix est installé. Le postfix suit.</p>")
        #expect(await tab.search("POSTFIX", direction: .forward) == true)
        #expect(try await selection(in: tab) == "Postfix@0")
        #expect(await tab.search("POSTFIX", direction: .forward) == true)
        #expect(try await selection(in: tab) == "postfix@25")
        // At the end, the search wraps around to the beginning, and backwards to the end.
        #expect(await tab.search("POSTFIX", direction: .forward) == true)
        #expect(try await selection(in: tab) == "Postfix@0")
        #expect(await tab.search("POSTFIX", direction: .backward) == true)
        #expect(try await selection(in: tab) == "postfix@25")
        #expect(await tab.search("zzqqxx", direction: .forward) == false)
    }

    /// Review WB13: ⌘E reads the real selection, even when the page redefines `getSelection`.
    @Test func `use selection reads the page's real selection`() async throws {
        let tab =
            try await page(
                "<p id='p'>texte choisi</p><script>window.getSelection = () => ({ toString: () => 'leurre', rangeCount: 0 });</script>",
            )
        _ = try await tab.loadedWebView.evaluateJavaScript(
            "document.getSelection().selectAllChildren(document.getElementById('p')); true",
            contentWorld: .defaultClient,
        )
        #expect(try await tab.loadedWebView.evaluateJavaScript("getSelection().toString()") as? String == "leurre")
        #expect(await PageFindResponder.selectedText(in: tab.loadedWebView) == "texte choisi")
    }

    @Test func `a growing query keeps the match in place`() async throws {
        let tab = try await page("<p>pomme poste</p>")
        #expect(await tab.search("p", direction: .forward) == true)
        #expect(await tab.search("po", direction: .forward) == true)
        #expect(try await selection(in: tab) == "po@0")
        #expect(await tab.search("pos", direction: .forward) == true)
        #expect(try await selection(in: tab) == "pos@6")
    }

    /// WebKit behavior, noted in `DECISIONS.md`: a letter without an accent also finds its accented forms,
    /// an accented letter only finds itself.
    @Test func `unaccented letters also find accented ones, not the reverse`() async throws {
        let accented = try await page("<p>Un été au café. Straße, œuvre.</p>")
        for query in ["ete", "éte", "ÉTÉ", "cafe", "strasse", "oeuvre"] {
            #expect(await accented.search(query, direction: .forward) == true, "\(query)")
        }
        let plain = try await page("<p>Un cafe.</p>")
        #expect(await plain.search("café", direction: .forward) == false)
    }

    @Test func `closing the bar deselects the match`() async throws {
        let tab = try await page("<p>Le postfix suit.</p>")
        tab.find.present()
        tab.find.updateQuery("postfix")
        await tab.find.waitForPendingSearch()
        #expect(tab.find.status == .found)
        #expect(try await selection(in: tab) == "postfix@3")

        tab.find.close()
        #expect(try await selection(in: tab).isEmpty)
    }

    @Test func `a new address forgets the result, unloading forgets the search`() async throws {
        let tab = try await page("<p>Le postfix suit.</p>")
        tab.find.present()
        tab.find.updateQuery("postfix")
        await tab.find.waitForPendingSearch()
        #expect(tab.find.status == .found)

        tab.load(TestPages.url("other"))
        try await waitUntil { tab.title == "other" }
        #expect(tab.find.isPresented)
        #expect(tab.find.query == "postfix")
        #expect(tab.find.status == .idle)

        tab.unload(resettingTo: nil, title: nil)
        #expect(!tab.find.isPresented)
        #expect(tab.find.query.isEmpty)
    }

    @Test func `a tab without a web view cannot search`() async {
        let tab = BrowserTab(configuration: TestPages.configuration())
        #expect(await tab.search("postfix", direction: .forward) == nil)
    }
}
