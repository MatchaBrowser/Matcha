import Foundation
@testable import Matcha
import Testing

/// History read by the command bar (`HistorySource`, task 5.5): a superset of what the ranking keeps, at most
/// `limit`, the best ones first.
@MainActor
struct HistoryIndexQueryTests {
    private let sample = HistoryIndex(visits: [
        historyVisit("https://github.com/apple/swift", title: "GitHub - apple/swift", minutesAgo: 10),
        historyVisit("https://github.com/apple/swift", title: "GitHub - apple/swift", minutesAgo: 20),
        historyVisit("https://nodejs.org/en/docs", title: "Node.js Documentation", minutesAgo: 30),
        historyVisit("https://www.lemonde.fr/", title: "Le Monde.fr - Actualités et Infos en France", minutesAgo: 40),
        historyVisit("https://fr.wikipedia.org/wiki/Caf%C3%A9", title: "Café — Wikipédia", minutesAgo: 50),
        historyVisit("file:///usr/share/doc/postfix/html/index.html", title: "Postfix Documentation", minutesAgo: 60),
        historyVisit("https://example.com/sans-titre", minutesAgo: 70),
        historyVisit("http://localhost:3000/admin", title: "Admin", minutesAgo: 80),
    ])

    /// Addresses that `CommandMatcher` accepts, one by one, with the title the bar gives them.
    private func bruteForce(_ text: String, in index: HistoryIndex) -> Set<String> {
        let query = CommandQuery(text: text, searchEngine: .google)
        return Set(index.entriesByKey.values.filter { entry in
            CommandMatcher.match(query, titles: [entry.title ?? CommandText.displayURL(entry.url)], url: entry.url) != nil
        }.map(\.urlKey))
    }

    private func found(_ text: String, in index: HistoryIndex, limit: Int = 300) -> [HistoryEntry] {
        index.entries(matching: CommandQuery(text: text, searchEngine: .google), limit: limit, now: fixedNow)
    }

    @Test func `the quick filter never hides a match`() {
        let texts = [
            "git", "GitHub", "apple swift", "gthb", "node.js", "nodejs", "node js", "docs", "cafe", "CAFÉ", "wiki caf",
            "lemonde", "le monde", "https://www.lem", "github.com/apple", "https://github.com/apple/swift#readme",
            "localhost:3000", "localhost:3000/admin", "postfix", "/usr/share", "sans-titre", "example.com/sans", "ex",
            "e", "z", "actu infos", "  ", "6.4", "c++",
        ]
        for text in texts {
            let keys = Set(found(text, in: sample).map { CommandText.urlKey($0.url) })
            #expect(keys == bruteForce(text, in: sample), "« \(text) »")
        }
    }

    @Test func `random queries match exactly what the matcher accepts`() {
        var generator = SeededGenerator(seed: 55)
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789 ./-éàç")
        for _ in 0 ..< 300 {
            let length = Int.random(in: 1 ... 6, using: &generator)
            let text = String((0 ..< length).map { _ in alphabet.randomElement(using: &generator)! })
            let keys = Set(found(text, in: sample).map { CommandText.urlKey($0.url) })
            #expect(keys == bruteForce(text, in: sample), "« \(text) »")
        }
    }

    @Test func `best matches come first and the limit is respected`() {
        let index = HistoryIndex(visits: [
            historyVisit("https://swift.org/", title: "Swift.org", minutesAgo: 60 * 24 * 100),
            historyVisit("https://forums.swift.org/", title: "Swift Forums", minutesAgo: 1),
            historyVisit("https://forums.swift.org/", title: "Swift Forums", minutesAgo: 2),
            historyVisit("https://developer.apple.com/swift/", title: "Apple Developer: Swift", minutesAgo: 3),
            historyVisit("https://taylorswift.com/", title: "Taylor Swift", minutesAgo: 4),
        ])
        // Prefix first (the most frequent and recent at the top), then start of a word, then substring.
        let titles = found("swift", in: index).map(\.title)
        #expect(titles == ["Swift Forums", "Swift.org", "Apple Developer: Swift", "Taylor Swift"])
        #expect(found("swift", in: index, limit: 2).map(\.title) == ["Swift Forums", "Swift.org"])
        #expect(found("swift", in: index, limit: 0).isEmpty)
        #expect(found("", in: index).isEmpty)
    }

    /// Review IU2: fuzzy matches are looked for only when the stricter ones leave room, and then come last.
    @Test func `fuzzy matches fill the room left by the strict ones`() {
        let index = HistoryIndex(visits: [
            historyVisit("https://github.com/", title: "GitHub", minutesAgo: 1),
            historyVisit("https://gthb.example/", title: "Gthb", minutesAgo: 60),
        ])
        #expect(found("gthb", in: index).map(\.title) == ["Gthb", "GitHub"])
        #expect(found("gthb", in: index, limit: 1).map(\.title) == ["Gthb"])
    }

    @Test func `a pasted address finds the same page`() {
        let entries = found("https://www.github.com/apple/swift/#readme", in: sample)
        #expect(entries.map(\.title) == ["GitHub - apple/swift"])
        #expect(entries.first?.visitCount == 2)
    }

    @Test func `the ranker keeps the same rows as with every entry`() {
        let ranker = CommandRanker()
        for text in ["git", "doc", "fr", "local", "swift", "post"] {
            let query = CommandQuery(text: text, searchEngine: .google)
            let all = sample.entriesByKey.values.map(\.historyEntry)
            let filtered = sample.entries(matching: query, limit: HistoryProvider.fetchLimit, now: fixedNow)
            #expect(rows(ranker, query, all) == rows(ranker, query, filtered), "« \(text) »")
        }
    }

    private func rows(_ ranker: CommandRanker, _ query: CommandQuery, _ entries: [HistoryEntry]) -> [String] {
        let candidates = entries.map { entry in
            CommandCandidate(
                kind: .history(visitCount: entry.visitCount, lastVisit: entry.lastVisit),
                title: entry.title ?? CommandText.displayURL(entry.url),
                url: entry.url,
            )
        }
        return ranker.rank(query, candidates: candidates, now: fixedNow).map(\.id)
    }
}
