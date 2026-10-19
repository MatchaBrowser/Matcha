import Foundation
@testable import Matcha
import Testing

/// History rules (task 5.5): what is recorded and when a visit extends another one.
struct HistoryRecordingPolicyTests {
    private func stored(_ address: String) -> String? {
        HistoryRecordingPolicy.storedURL(for: URL(string: address))?.absoluteString
    }

    @Test func `web pages and local files are recorded`() {
        #expect(stored("https://example.com/a?b=c") == "https://example.com/a?b=c")
        #expect(stored("http://localhost:8080/") == "http://localhost:8080/")
        #expect(stored("HTTPS://Example.com/") != nil)
        #expect(stored("file:///usr/share/doc/postfix/html/index.html") == "file:///usr/share/doc/postfix/html/index.html")
    }

    @Test func `other schemes and pages without host are never recorded`() {
        for address in [
            "about:blank", "about:blank?one", "data:text/html,hello", "blob:https://example.com/1234", "javascript:alert(1)",
            "obtest://pages/a", "mailto:a@example.com", "https:///chemin", "webkit-pdf://x",
        ] {
            #expect(stored(address) == nil, "\(address)")
        }
        #expect(HistoryRecordingPolicy.storedURL(for: nil) == nil)
    }

    @Test func `fragment and credentials are dropped`() {
        #expect(stored("https://user:secret@example.com/docs#section-2") == "https://example.com/docs")
        #expect(stored("https://example.com/#") == "https://example.com/")
        #expect(stored("file:///tmp/page.html#top") == "file:///tmp/page.html")
    }

    @Test func `titles are trimmed and empty ones dropped`() {
        #expect(HistoryRecordingPolicy.normalizedTitle("  Exemple \n") == "Exemple")
        #expect(HistoryRecordingPolicy.normalizedTitle(" \n ") == nil)
        #expect(HistoryRecordingPolicy.normalizedTitle(nil) == nil)
    }

    @Test func `the same address reloaded shortly after refreshes the visit`() {
        let start = fixedNow
        let previous = HistoryRecordingPolicy.PageVisit(id: UUID(), urlKey: "example.com", date: start)
        #expect(HistoryRecordingPolicy.decision(previous: nil, urlKey: "example.com", now: start) == .record)
        #expect(HistoryRecordingPolicy.decision(previous: previous, urlKey: "example.com", now: start) == .refresh)
        #expect(HistoryRecordingPolicy.decision(previous: previous, urlKey: "example.com", now: start + 60) == .refresh)
        #expect(HistoryRecordingPolicy.decision(previous: previous, urlKey: "example.com", now: start + 61) == .record)
        #expect(HistoryRecordingPolicy.decision(previous: previous, urlKey: "example.com/autre", now: start + 1) == .record)
    }

    @Test func `a late title renames the visit only shortly after or when it had none`() {
        let visit = HistoryRecordingPolicy.PageVisit(id: UUID(), urlKey: "example.com", date: fixedNow)
        func accepts(hasTitle: Bool, key: String? = "example.com", after seconds: TimeInterval) -> Bool {
            HistoryRecordingPolicy.acceptsTitle(for: visit, visitHasTitle: hasTitle, pageURLKey: key, now: fixedNow + seconds)
        }
        #expect(accepts(hasTitle: true, after: 5))
        #expect(!accepts(hasTitle: true, after: 6))
        #expect(accepts(hasTitle: false, after: 3600))
        // The page is already elsewhere: the title is that of another page.
        #expect(!accepts(hasTitle: false, key: "example.com/autre", after: 1))
        #expect(!accepts(hasTitle: false, key: nil, after: 1))
    }

    @Test func `an address changed by the page must keep the origin of the loaded document`() throws {
        let loaded = try #require(URL(string: "https://www.youtube.com/"))
        func change(_ address: String) throws -> Bool {
            try HistoryRecordingPolicy.isSameDocumentChange(from: loaded, to: #require(URL(string: address)))
        }
        #expect(try change("https://www.youtube.com/watch?v=1"))
        #expect(try change("https://WWW.YouTube.com/feed"))
        #expect(try !change("https://youtube.com/watch?v=1"))
        #expect(try !change("http://www.youtube.com/watch?v=1"))
        #expect(try !change("https://www.youtube.com:8443/watch"))
        #expect(try !change("https://example.com/"))
        #expect(try !HistoryRecordingPolicy.isSameDocumentChange(from: nil, to: #require(URL(string: "https://example.com/"))))
    }

    @Test func `history is kept one year`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 9)))
        let cutoff = HistoryRecordingPolicy.retentionCutoff(now: now, calendar: calendar)
        #expect(cutoff == calendar.date(from: DateComponents(year: 2025, month: 10, day: 18, hour: 9)))
        // February 29: one year earlier is the day before (February 28).
        let leap = try #require(calendar.date(from: DateComponents(year: 2028, month: 2, day: 29, hour: 12)))
        let leapCutoff = HistoryRecordingPolicy.retentionCutoff(now: leap, calendar: calendar)
        #expect(leapCutoff == calendar.date(from: DateComponents(year: 2027, month: 2, day: 28, hour: 12)))
    }
}
