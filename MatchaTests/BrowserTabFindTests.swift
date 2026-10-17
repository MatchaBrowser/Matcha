import Foundation
@testable import Matcha
import Testing
import WebKit

/// Recherche dans une vraie page (tâche 5.3) : ce que fait `WKWebView.find(_:configuration:)` derrière
/// `BrowserTab.search`, et la recherche de l'onglet (désélection, page déchargée ou changée).
@MainActor
struct BrowserTabFindTests {
    /// Onglet sur une page locale dont le corps est `body`.
    private func page(_ body: String) async throws -> BrowserTab {
        let tab = BrowserTab(configuration: TestPages.configuration())
        tab.load(TestPages.url("find", body: body))
        try await waitUntil { tab.title == "find" && !tab.isLoading }
        return tab
    }

    /// Texte sélectionné dans la page et sa position dans son nœud.
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
        // Au bout, la recherche repart du début, et à rebours de la fin.
        #expect(await tab.search("POSTFIX", direction: .forward) == true)
        #expect(try await selection(in: tab) == "Postfix@0")
        #expect(await tab.search("POSTFIX", direction: .backward) == true)
        #expect(try await selection(in: tab) == "postfix@25")
        #expect(await tab.search("zzqqxx", direction: .forward) == false)
    }

    @Test func `a growing query keeps the match in place`() async throws {
        let tab = try await page("<p>pomme poste</p>")
        #expect(await tab.search("p", direction: .forward) == true)
        #expect(await tab.search("po", direction: .forward) == true)
        #expect(try await selection(in: tab) == "po@0")
        #expect(await tab.search("pos", direction: .forward) == true)
        #expect(try await selection(in: tab) == "pos@6")
    }

    /// Comportement de WebKit, noté dans `DECISIONS.md` : une lettre sans accent trouve aussi ses formes accentuées,
    /// une lettre accentuée ne trouve qu'elle-même.
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
