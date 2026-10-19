import Foundation
@testable import Matcha
import Testing

/// Fake search: the texts present in the page, the searches requested, the deselections. With `gate`, each search
/// waits for `gate.open()`.
@MainActor
final class FakeFindPerformer: FindPerformer {
    struct Search: Equatable {
        let query: String
        let direction: FindDirection
    }

    var matches: Set<String> = []
    /// Fake: the page cannot search (no web view).
    var canSearch = true
    var gate: GatedSleep?
    private(set) var searches: [Search] = []
    private(set) var deselections = 0

    func search(_ query: String, direction: FindDirection) async -> Bool? {
        searches.append(Search(query: query, direction: direction))
        try? await gate?.sleep(.zero)
        return canSearch ? matches.contains(query) : nil
    }

    func deselectMatch() {
        deselections += 1
    }
}

/// Find in page (task 5.3): opening and keyboard focus, deferred and cancelled typing, next and previous, closing,
/// page unloaded or changed.
@MainActor
struct FindSessionTests {
    private let page = FakeFindPerformer()
    private let sleeper = FakeSleep()

    /// Search on `page`, immediate wait (or `gate`).
    private func makeSession(gate: GatedSleep? = nil) -> FindSession {
        let session = if let gate {
            FindSession { try await gate.sleep($0) }
        } else {
            FindSession { [sleeper] in try await sleeper.sleep($0) }
        }
        session.performer = page
        return session
    }

    private func search(_ query: String, _ direction: FindDirection = .forward) -> FakeFindPerformer.Search {
        FakeFindPerformer.Search(query: query, direction: direction)
    }

    /// Bar open, `text` typed and searched.
    private func type(_ text: String, in session: FindSession) async {
        session.present()
        session.updateQuery(text)
        await session.waitForPendingSearch()
    }

    @Test func `⌘F opens the bar and asks the field for the keyboard each time`() {
        let session = makeSession()
        #expect(!session.isPresented)
        #expect(!session.takeFocusRequest())

        session.present()
        #expect(session.isPresented)
        #expect(session.takeFocusRequest())
        // A field recreated later (back on the tab) does not take the keyboard focus back.
        #expect(!session.takeFocusRequest())

        // Already open: it stays, and the field takes the keyboard focus back.
        session.present()
        #expect(session.isPresented)
        #expect(session.takeFocusRequest())
        #expect(page.searches.isEmpty)
    }

    @Test func `typing searches forward after 150 ms`() async {
        page.matches = ["postfix"]
        let session = makeSession()
        await type("postfix", in: session)
        #expect(sleeper.durations == [.milliseconds(150)])
        #expect(page.searches == [search("postfix")])
        #expect(session.status == .found)
        #expect(session.hasQuery)
    }

    @Test func `a query found nowhere is not found`() async {
        let session = makeSession()
        await type("zzqqxx", in: session)
        #expect(session.status == .notFound)
    }

    @Test func `a newer keystroke cancels the pending search`() async throws {
        let gate = GatedSleep()
        let session = makeSession(gate: gate)
        session.present()
        session.updateQuery("p")
        session.updateQuery("po")
        try await waitUntil { gate.waitingCount == 2 }
        gate.open()
        await session.waitForPendingSearch()
        await Task.yield()
        #expect(page.searches == [search("po")])
    }

    @Test func `clearing the field cancels the search and forgets the result`() async throws {
        page.matches = ["p"]
        let gate = GatedSleep()
        let session = makeSession(gate: gate)
        session.present()
        session.updateQuery("p")
        try await waitUntil { gate.waitingCount == 1 }
        session.updateQuery("")
        gate.open()
        await Task.yield()
        #expect(page.searches.isEmpty)
        #expect(session.status == .idle)
        #expect(!session.hasQuery)
    }

    @Test func `the Return key and ⌘G search at once, forward or backward`() async throws {
        page.matches = ["postfix"]
        let session = makeSession()
        await type("postfix", in: session)
        session.findNext()
        await session.waitForPendingSearch()
        session.findPrevious()
        await session.waitForPendingSearch()
        #expect(page.searches == [search("postfix"), search("postfix"), search("postfix", .backward)])

        // Return before the end of the wait: the pending input is searched right away, only once.
        let gate = GatedSleep()
        let typing = makeSession(gate: gate)
        typing.present()
        typing.updateQuery("abc")
        typing.findNext()
        await typing.waitForPendingSearch()
        try await waitUntil { gate.waitingCount == 1 }
        gate.open()
        await Task.yield()
        #expect(page.searches.suffix(1) == [search("abc")])
        #expect(page.searches.count == 4)
        #expect(typing.status == .notFound)
    }

    @Test func `next and previous need a query`() {
        let session = makeSession()
        session.findNext()
        session.findPrevious()
        #expect(!session.isPresented)
        #expect(page.searches.isEmpty)
    }

    @Test func `⌘G reopens a closed bar without taking the keyboard`() async {
        page.matches = ["postfix"]
        let session = makeSession()
        await type("postfix", in: session)
        #expect(session.takeFocusRequest())
        session.close()

        session.findNext()
        #expect(session.isPresented)
        #expect(!session.takeFocusRequest())
        await session.waitForPendingSearch()
        #expect(session.status == .found)
    }

    @Test func `closing deselects the match only after a successful search and keeps the query`() async {
        page.matches = ["postfix"]
        let session = makeSession()
        await type("postfix", in: session)
        session.close()
        #expect(!session.isPresented)
        #expect(session.query == "postfix")
        #expect(session.hasQuery)
        #expect(session.status == .idle)
        #expect(page.deselections == 1)

        // Nothing found: the page's selection is not ours, it stays.
        await type("zzqqxx", in: session)
        session.close()
        #expect(page.deselections == 1)
    }

    @Test func `closing during a search ignores its result`() async throws {
        page.matches = ["postfix"]
        let gate = GatedSleep()
        page.gate = gate
        let session = makeSession()
        session.present()
        session.updateQuery("postfix")
        try await waitUntil { gate.waitingCount == 1 }
        session.close()
        gate.open()
        // The cancelled search resumes and finishes: its result must not change anything.
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.status == .idle)
        session.close()
        #expect(page.deselections == 0)
    }

    @Test func `an unloaded page forgets everything without touching the page`() async {
        page.matches = ["postfix"]
        let session = makeSession()
        await type("postfix", in: session)
        session.reset()
        #expect(!session.isPresented)
        #expect(session.query.isEmpty)
        #expect(!session.hasQuery)
        #expect(session.status == .idle)
        #expect(page.deselections == 0)
    }

    @Test func `a new address forgets the result but keeps the bar`() async {
        page.matches = ["postfix"]
        let session = makeSession()
        await type("postfix", in: session)
        session.pageDidChange()
        #expect(session.isPresented)
        #expect(session.query == "postfix")
        #expect(session.status == .idle)
        session.close()
        #expect(page.deselections == 0)
    }

    @Test func `a page that cannot search shows no result`() async {
        page.canSearch = false
        let session = makeSession()
        await type("postfix", in: session)
        #expect(session.status == .idle)
    }

    @Test func `field commands come after the input method`() {
        #expect(FindKeyCommand(selectorName: "insertNewline:", isShiftDown: false) == .next)
        #expect(FindKeyCommand(selectorName: "insertNewline:", isShiftDown: true) == .previous)
        #expect(FindKeyCommand(selectorName: "insertNewlineIgnoringFieldEditor:", isShiftDown: false) == .next)
        #expect(FindKeyCommand(selectorName: "insertLineBreak:", isShiftDown: true) == .previous)
        #expect(FindKeyCommand(selectorName: "cancelOperation:", isShiftDown: false) == .close)
        #expect(FindKeyCommand(selectorName: "complete:", isShiftDown: false) == .close)
        // ⇥, ↑ and ↓ stay with the editor (next field, cursor).
        for selector in ["insertTab:", "insertBacktab:", "moveUp:", "moveDown:", "deleteBackward:"] {
            #expect(FindKeyCommand(selectorName: selector, isShiftDown: false) == nil)
        }
    }
}
