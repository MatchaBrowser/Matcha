import Foundation
@testable import Matcha
import Testing

/// Deduplication, caps and suggestions of the command bar.
struct CommandRankerFilteringTests {
    private let ranker = CommandRanker()

    private func rank(_ text: String, _ candidates: [CommandCandidate]) -> [CommandRow] {
        ranker.rank(query(text), candidates: candidates, now: fixedNow)
    }

    /// Rows that follow the rows of the typed text.
    private func resultRows(_ rows: [CommandRow]) -> [CommandRow] {
        rows.filter { !$0.id.hasPrefix(CommandPrimaryRows.id) }
    }

    @Test func `open tab hides history with the same address`() {
        let open = tab("Example", url: "http://example.com")
        let candidates = [history("Example Domain", url: "https://www.example.com/", visits: 20), open]
        #expect(resultRows(rank("exam", candidates)).map(\.id) == [open.id])
    }

    @Test func `history equal to the typed address is dropped`() {
        let docs = history("Example docs", url: "https://example.com/docs")
        let candidates = [history("Example", url: "https://example.com/", visits: 20), docs]
        let rows = rank("example.com", candidates)
        #expect(rows.first?.style == .openAddress)
        #expect(resultRows(rows).map(\.id) == [docs.id])
        #expect(resultRows(rows).first?.subtitle == "example.com/docs")
    }

    @Test func `duplicate history keys keep the best frecency`() throws {
        let candidates = [
            history("News old", url: "http://www.news.example/", visits: 2, daysAgo: 1),
            history("News fresh", url: "https://news.example", visits: 9, daysAgo: 1),
            history("News stale", url: "https://news.example/", visits: 9, daysAgo: 40),
        ]
        let rows = resultRows(rank("news", candidates))
        #expect(rows.map(\.title) == ["News fresh"])
        #expect(try rows.first?.target == .open(#require(URL(string: "https://news.example"))))
    }

    @Test func `the same tab id is listed once, first copy kept`() {
        let id = UUID()
        let candidates = [
            tab("First copy", url: "https://a.example", id: id),
            tab("Second copy", url: "https://a.example", id: id),
        ]
        #expect(resultRows(rank("copy", candidates)).map(\.title) == ["First copy"])
    }

    @Test func `two tabs on the same address are both listed`() {
        let candidates = [tab("Doc", url: "https://doc.example"), tab("Doc", url: "https://doc.example")]
        #expect(resultRows(rank("doc", candidates)).count == 2)
    }

    @Test func `local rows are capped per kind and in total`() {
        let tabs = (1 ... 6).map { tab("Item \($0)", url: "https://tab\($0).example") }
        let entries = (1 ... 5).map { history("Item h\($0)", url: "https://history\($0).example") }
        let rows = resultRows(rank("item", entries + tabs))
        #expect(rows.count == 6)
        #expect(rows.filter {
            if case .tab = $0.style {
                true
            } else {
                false
            }
        }.count == 4)
        #expect(rows.filter { $0.style == .history }.count == 2)

        let historyOnly = resultRows(rank("item", entries))
        #expect(historyOnly.count == 4)
        #expect(historyOnly.allSatisfy { $0.style == .history })

        // Three actions match “c a” (the third one, a fake, through its keywords): the cap
        // on actions (2) keeps the first two of the uncapped order.
        let closeAll = CommandCandidate(kind: .action(.settings, keywords: ["close", "all"]), title: "Settings", url: nil)
        let actions = [action(.newSpace), action(.copyURL), closeAll]
        var uncapped = CommandRanker()
        uncapped.limits.actions = 3
        let all = resultRows(uncapped.rank(query("c a"), candidates: actions, now: fixedNow))
        #expect(all.count == 3)
        let found = resultRows(rank("c a", actions))
        #expect(found.count == 2)
        #expect(found.map(\.id) == all.prefix(2).map(\.id))
    }

    @Test func `suggestions come after local rows in engine order`() throws {
        let candidates = [
            suggestion("pain perdu"),
            suggestion("pain au levain"),
            tab("Pain recipes", url: "https://pain.example"),
            suggestion("pain de mie"),
        ]
        let rows = rank("pain", candidates)
        #expect(rows.map(\.title) == ["pain", "Pain recipes", "pain perdu", "pain au levain", "pain de mie"])
        let last = rows.last
        #expect(last?.id == "suggestion:pain de mie")
        #expect(last?.style == .suggestion)
        #expect(try last?.target == .open(#require(URL(string: "https://www.google.com/search?q=pain%20de%20mie"))))
    }

    @Test func `suggestions equal to the query or duplicated are dropped and capped at four`() {
        let texts = ["pain au levain", "PAIN AU LEVAIN", "pain au", "pain au chocolat", "pain aux raisins", "pain au lait", "pain"]
        let rows = rank("pain au", texts.map(suggestion)).filter { $0.style == .suggestion }
        #expect(rows.map(\.title) == ["pain au levain", "pain au chocolat", "pain aux raisins", "pain au lait"])
    }

    @Test func `suggestions are ignored when the text is an address`() {
        let rows = rank("apple.com", [suggestion("apple.com login"), suggestion("apple.com support")])
        #expect(!rows.contains { $0.style == .suggestion })
        #expect(rows.count == 2)
    }

    @Test func `actions match title or keywords, never loosely`() {
        let actions = CommandActionID.allCases.map(action)
        #expect(resultRows(rank("pref", actions)).map(\.style) == [.action(.settings)])
        #expect(resultRows(rank("Sett", actions)).map(\.style) == [.action(.settings)])
        #expect(resultRows(rank("s", actions)).isEmpty)
        #expect(resultRows(rank("stg", actions)).isEmpty)
        #expect(resultRows(rank("ttings", actions)).isEmpty)
    }

    @Test func `carried over suggestions keep those extending the text`() {
        let suggestions = [suggestion("pain au levain"), suggestion("Pain perdu"), suggestion("painting"), suggestion("baguette")]
        let extended = CommandRanker.carriedOver(suggestions, to: query("pain p"))
        #expect(extended.map(\.title) == ["Pain perdu"])
        let shorter = CommandRanker.carriedOver(suggestions, to: query("PAIN"))
        #expect(shorter.map(\.title) == ["pain au levain", "Pain perdu", "painting"])
    }

    @Test func `pristine rows are the current address then copy url`() throws {
        let url = try #require(URL(string: "about:blank?one"))
        let rows = ranker.pristineRows(currentURL: url, actions: CommandActionID.allCases.reversed().map(action))
        #expect(rows.map(\.id) == [CommandPrimaryRows.id, "action:copyURL"])
        #expect(rows.first == CommandPrimaryRows.current(url))
        #expect(rows[1].target == .perform(.copyURL))
        #expect(rows[1].title == "Copy URL")

        let withoutCopy = ranker.pristineRows(currentURL: url, actions: [action(.newSpace), action(.settings)])
        #expect(withoutCopy.map(\.id) == [CommandPrimaryRows.id])
    }
}
