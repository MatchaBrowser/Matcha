import Foundation
@testable import Matcha
import Testing

/// Ordre des lignes de la barre de commande (tests de classement demandés par le plan).
struct CommandRankerTests {
    private let ranker = CommandRanker()

    /// Titres des lignes qui suivent les lignes du texte tapé.
    private func localTitles(_ rows: [CommandRow]) -> [String] {
        rows.filter { !$0.id.hasPrefix(CommandPrimaryRows.id) && $0.style != .suggestion }.map(\.title)
    }

    private func rank(_ text: String, _ candidates: [CommandCandidate], ranker: CommandRanker? = nil) -> [CommandRow] {
        (ranker ?? self.ranker).rank(query(text), candidates: candidates, now: fixedNow)
    }

    @Test func `empty query has no rows`() {
        let candidates = [tab("About", url: "https://a.example"), action(.settings), suggestion("a")]
        #expect(rank("", candidates).isEmpty)
        #expect(rank("  \n", candidates).isEmpty)
    }

    @Test func `first row stays first even with a perfect tab match`() {
        let github = tab("GitHub", url: "https://github.com/")
        let rows = rank("GitHub", [github])
        #expect(rows.map(\.id) == [CommandPrimaryRows.id, github.id])
        #expect(rows.first?.style == .search)

        let byAddress = rank("github.com", [github])
        #expect(byAddress.map(\.id) == [CommandPrimaryRows.id, CommandPrimaryRows.searchAlternativeID, github.id])
        #expect(byAddress.first?.style == .openAddress)
    }

    @Test func `match tiers order rows of the same kind`() {
        var ranker = CommandRanker()
        ranker.limits.history = 5
        let candidates = [
            history("Great Interior Tour", url: "https://e.example/5", visits: 3, daysAgo: 1),
            history("Legit Stuff", url: "https://d.example/4", visits: 3, daysAgo: 1),
            history("Git", url: "https://a.example/1", visits: 3, daysAgo: 1),
            history("Learn Git Now", url: "https://c.example/3", visits: 3, daysAgo: 1),
            history("GitHub", url: "https://b.example/2", visits: 3, daysAgo: 1),
        ]
        let titles = localTitles(rank("git", candidates, ranker: ranker))
        #expect(titles == ["Git", "GitHub", "Learn Git Now", "Legit Stuff", "Great Interior Tour"])
    }

    @Test func `history prefix beats fuzzy whatever the frecency`() {
        let candidates = [
            history("GitHub", url: "https://github.com", visits: 500, daysAgo: 0),
            history("gthb tracker", url: "https://tracker.example/gthb", visits: 1, daysAgo: 200),
        ]
        #expect(localTitles(rank("gthb", candidates)) == ["gthb tracker", "GitHub"])
    }

    @Test func `tier and fuzzy quality come before the kind`() {
        // Préfixe d'une entrée d'historique peu visitée avant un onglet du Space affiché trouvé de
        // façon approximative.
        let byTier = [
            tab("GitHub", url: "https://github.com", activity: fixedNow),
            history("gthb tracker", url: "https://tracker.example/gthb", visits: 1, daysAgo: 200),
        ]
        #expect(localTitles(rank("gthb", byTier)) == ["gthb tracker", "GitHub"])

        // Deux correspondances approximatives : la plus compacte (tranche 3, qualité 80) avant
        // l'onglet du Space affiché (tranche 1, qualité 36).
        let byBucket = [
            tab("Google Drive", url: "https://drive.example", activity: fixedNow),
            history("gdrive notes", url: "https://notes.example", visits: 1, daysAgo: 200),
        ]
        #expect(localTitles(rank("gdrv", byBucket)) == ["gdrive notes", "Google Drive"])
    }

    @Test func `history in a tier follows frecency then recency`() {
        let byFrecency = [
            history("Excel", url: "https://excel.com", visits: 30, daysAgo: 60),
            history("Example", url: "https://example.com", visits: 10, daysAgo: 2),
        ]
        #expect(localTitles(rank("ex", byFrecency)) == ["Example", "Excel"])

        let byVisits = [
            history("Exa one", url: "https://one.example", visits: 1, daysAgo: 0),
            history("Exa three", url: "https://three.example", visits: 3, daysAgo: 0),
        ]
        #expect(localTitles(rank("ex", byVisits)) == ["Exa three", "Exa one"])

        let byRecency = [
            history("Exa alpha", url: "https://alpha.example", visits: 2, daysAgo: 3),
            history("Exa beta", url: "https://beta.example", visits: 2, daysAgo: 1),
        ]
        #expect(localTitles(rank("ex", byRecency)) == ["Exa beta", "Exa alpha"])
    }

    @Test func `kinds in a tier: shown space tab, other space tab, action, history`() {
        let candidates = [
            history("Settle down", url: "https://settle.example", visits: 30, daysAgo: 0),
            action(.settings),
            tab("Settlement plan", url: "https://plan.example", spaceName: "Travail", activity: fixedNow),
            tab("Settlers wiki", url: "https://settlers.example", activity: fixedNow.addingTimeInterval(-3600)),
        ]
        let rows = rank("sett", candidates)
        #expect(localTitles(rows) == ["Settlers wiki", "Settlement plan", "Settings", "Settle down"])
        #expect(rows.last?.style == .history)
        #expect(rows[3].style == .action(.settings))
        #expect(rows[3].target == .perform(.settings))
    }

    @Test func `tabs in a tier by most recent activity`() {
        let candidates = [
            tab("Doc A", url: "https://a.example", activity: fixedNow.addingTimeInterval(-300)),
            tab("Doc B", url: "https://b.example", activity: fixedNow.addingTimeInterval(-10)),
            tab("Doc C", url: "https://c.example", activity: fixedNow.addingTimeInterval(-100)),
        ]
        #expect(localTitles(rank("doc", candidates)) == ["Doc B", "Doc C", "Doc A"])
    }

    @Test func `ties fall back to title then id`() throws {
        let first = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let second = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let candidates = [
            tab("Same doc", url: "https://two.example", id: second),
            tab("Beta doc", url: "https://beta.example"),
            tab("Same doc", url: "https://one.example", id: first),
            tab("alpha doc", url: "https://alpha.example"),
        ]
        let rows = rank("doc", candidates)
        #expect(localTitles(rows) == ["alpha doc", "Beta doc", "Same doc", "Same doc"])
        #expect(rows.suffix(2).map(\.url?.absoluteString) == ["https://one.example", "https://two.example"])
    }

    @Test func `other space tabs carry the space name`() throws {
        let budget = tab("Budget", url: "https://www.sheets.example/budget", place: .pinned, spaceName: "Travail")
        guard case let .tab(reference, _, _, _) = budget.kind else {
            Issue.record("Onglet attendu")
            return
        }
        let row = try #require(rank("budget", [budget]).last)
        #expect(row.id == budget.id)
        #expect(row.style == .tab(reference, place: .pinned, spaceName: "Travail"))
        #expect(row.subtitle == "sheets.example")
        #expect(row.target == .switchToTab(reference))

        let shown = try #require(rank("example", [tab("example.com", url: "https://example.com")]).last)
        #expect(shown.subtitle == nil)
    }

    @Test func `order does not depend on candidate order`() {
        let candidates = [
            tab("Paris trip", url: "https://paris.example", activity: fixedNow.addingTimeInterval(-60)),
            tab("Pain recipes", url: "https://pain.example", activity: fixedNow.addingTimeInterval(-60)),
            tab("Spa day", url: "https://spa.example", spaceName: "Maison"),
            tab("Pain recipes", url: "https://pain.example/2", activity: fixedNow.addingTimeInterval(-60)),
            history("Paper", url: "https://paper.example", visits: 4, daysAgo: 1),
            history("Panda", url: "https://panda.example", visits: 4, daysAgo: 1),
            history("Pasta", url: "https://pasta.example", visits: 9, daysAgo: 20),
            history("Pasta again", url: "http://www.pasta.example/", visits: 9, daysAgo: 20),
            history("Patio", url: "https://patio.example", visits: 1, daysAgo: 100),
            action(.newSpace),
            action(.settings),
            suggestion("pa"),
        ]
        let expected = rank("pa", candidates)
        #expect(expected.count > 6)
        var generator = SeededGenerator(seed: 41)
        for _ in 0 ..< 10 {
            #expect(rank("pa", candidates.shuffled(using: &generator)) == expected)
        }
    }
}
