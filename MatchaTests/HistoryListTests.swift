import AppKit
import Foundation
@testable import Matcha
import Testing

/// History window (task 5.5), without UI: cleared periods, days, rows and search.
struct HistoryListTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func visit(_ address: String, title: String? = nil, at date: Date) -> HistoryVisit {
        HistoryVisit(url: URL(string: address)!, title: title, date: date)
    }

    // MARK: Periods

    @Test func `clear periods start at the expected time`() {
        let now = date(18, 9, 30)
        #expect(HistoryPeriod.lastHour.start(now: now, calendar: calendar) == date(18, 8, 30))
        #expect(HistoryPeriod.today.start(now: now, calendar: calendar) == date(18, 0))
        #expect(HistoryPeriod.todayAndYesterday.start(now: now, calendar: calendar) == date(17, 0))
        #expect(HistoryPeriod.allHistory.start(now: now, calendar: calendar) == nil)
    }

    @Test func `each button of the clear alert is its period, then cancel`() {
        let first = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let periods = (0 ..< 5).map { HistoryClearAlert.period(for: NSApplication.ModalResponse(rawValue: first + $0)) }
        #expect(periods == [.lastHour, .today, .todayAndYesterday, .allHistory, nil])
        #expect(HistoryClearAlert.period(for: .cancel) == nil)
        #expect(HistoryClearAlert.period(for: .abort) == nil)
    }

    @Test func `clear periods follow daylight saving changes`() {
        // On October 25, 2026, the day lasts 25 hours in Paris; on March 29, 23 hours.
        #expect(HistoryPeriod.todayAndYesterday.start(now: date(26, 0, 30), calendar: calendar) == date(25, 0))
        #expect(HistoryPeriod.today.start(now: date(25, 23, 59), calendar: calendar) == date(25, 0))
        let march = date(30, 1, month: 3)
        #expect(HistoryPeriod.todayAndYesterday.start(now: march, calendar: calendar) == date(29, 0, month: 3))
        // One hour before 3:30 on the day of the switch to summer time: 1:30 (2:00 does not exist).
        #expect(HistoryPeriod.lastHour.start(now: date(29, 3, 30, month: 3), calendar: calendar) == date(29, 1, 30, month: 3))
    }

    // MARK: Days and rows

    @Test func `visits are grouped by day then by address`() throws {
        let now = date(18, 12)
        let index = HistoryIndex(visits: [
            visit("https://example.com/", title: "Exemple", at: date(18, 9)),
            visit("https://www.example.com/", title: "Exemple", at: date(18, 11)),
            visit("https://apple.com/", title: "Apple", at: date(18, 10)),
            visit("https://example.com/", title: "Exemple", at: date(17, 23, 59)),
            visit("https://swift.org/", at: date(15, 0)),
            // Exactly midnight: the day that starts.
            visit("https://minuit.example/", at: date(16, 0)),
        ])
        let sections = HistoryList.sections(from: index, search: "", now: now, calendar: calendar)
        #expect(sections.map(\.day) == [.today, .yesterday, .date(date(16, 0)), .date(date(15, 0))])
        #expect(sections.map(\.start) == [date(18, 0), date(17, 0), date(16, 0), date(15, 0)])

        let today = try #require(sections.first)
        #expect(today.rows.map(\.title) == ["Exemple", "Apple"])
        let example = try #require(today.rows.first)
        #expect(example.lastVisit == date(18, 11))
        #expect(example.visitIDs.count == 2)
        #expect(example.host == "example.com")
        #expect(sections[1].rows.map(\.visitIDs.count) == [1])
        // Without a title: the readable address.
        #expect(sections[3].rows.map(\.title) == ["swift.org"])
        // Identifiers unique from one day to the next.
        let ids = sections.flatMap { $0.rows.map(\.id) }
        #expect(Set(ids).count == ids.count)
    }

    @Test func `search looks at titles and addresses without case or accents`() {
        let now = date(18, 12)
        let index = HistoryIndex(visits: [
            visit("https://fr.wikipedia.org/wiki/Caf%C3%A9", title: "Café — Wikipédia", at: date(18, 9)),
            visit("https://developer.apple.com/documentation/", title: "Apple Developer Documentation", at: date(17, 9)),
            visit("file:///usr/share/doc/postfix/html/index.html", title: "Postfix Documentation", at: date(16, 9)),
        ])
        func titles(_ search: String) -> [String] {
            HistoryList.sections(from: index, search: search, now: now, calendar: calendar).flatMap { $0.rows.map(\.title) }
        }
        #expect(titles("CAFE") == ["Café — Wikipédia"])
        #expect(titles("wikipedia.org") == ["Café — Wikipédia"])
        #expect(titles("documentation") == ["Apple Developer Documentation", "Postfix Documentation"])
        #expect(titles("apple doc") == ["Apple Developer Documentation"])
        #expect(titles("/usr/share") == ["Postfix Documentation"])
        #expect(titles("zzz").isEmpty)
        #expect(titles("  ").count == 3)
    }

    @Test func `an empty history has no section`() {
        #expect(HistoryList.sections(from: HistoryIndex(), search: "", now: date(18, 12), calendar: calendar).isEmpty)
    }
}
