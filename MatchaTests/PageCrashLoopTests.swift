import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

/// Page that crashes in a loop (task 5.7): on the second termination within 30 s, no more automatic reload, a message
/// waits for the user; the reload after a termination is not a history visit. Real web views, terminations reported
/// to the delegate as WebKit does, test clock.
@MainActor
@Suite(.webKit)
struct PageCrashLoopTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let pages = CountingTestPages()
    private let clock = TestClock()

    init() {
        manager.coordinator.now = { [clock] in clock.now }
    }

    /// Selected tab on the local page “page”, once loaded.
    private func openTab() async throws -> BrowserTab {
        let tab = manager.insertTab(configuration: pages.configuration(), after: nil, select: true)
        tab.load(TestPages.url("page"))
        try await waitUntil { tab.title == "page" && !tab.isLoading }
        return tab
    }

    private func terminate(_ tab: BrowserTab) throws {
        try manager.coordinator.webViewWebContentProcessDidTerminate(#require(tab.webView))
    }

    /// Reload finished: `count` requests in all for the page, resumption done.
    private func waitForReload(of tab: BrowserTab, requests count: Int) async throws {
        try await waitUntil { pages.count("page") == count && !tab.crash.isRecovering && !tab.isLoading }
    }

    @Test func `a second crash within 30 seconds shows the message and waits for the user`() async throws {
        let tab = try await openTab()
        try terminate(tab)
        try await waitForReload(of: tab, requests: 2)

        clock.advance(10)
        try terminate(tab)
        #expect(tab.crash.isShowingProblem)
        #expect(tab.keepsTitleAndAddress)
        #expect(tab.webView != nil)
        #expect(tab.title == "page")
        #expect(tab.url == TestPages.url("page"))
        try await Task.sleep(for: .milliseconds(200))
        #expect(pages.count("page") == 2)

        // The message's “Reload” button, like ⌘R: the message goes away right away.
        tab.reload()
        #expect(!tab.crash.isShowingProblem)
        try await waitForReload(of: tab, requests: 3)

        // Still within the 30 s: the message again.
        clock.advance(5)
        try terminate(tab)
        #expect(tab.crash.isShowingProblem)
    }

    @Test func `crashes far apart reload each time`() async throws {
        let tab = try await openTab()
        try terminate(tab)
        try await waitForReload(of: tab, requests: 2)
        clock.advance(31)
        try terminate(tab)
        #expect(!tab.crash.isShowingProblem)
        try await waitForReload(of: tab, requests: 3)
    }

    @Test func `another address leaves the message`() async throws {
        let tab = try await openTab()
        try terminate(tab)
        try await waitForReload(of: tab, requests: 2)
        try terminate(tab)
        #expect(tab.crash.isShowingProblem)

        tab.load(TestPages.url("ailleurs"))
        #expect(!tab.crash.isShowingProblem)
        try await waitUntil { tab.title == "ailleurs" && !tab.crash.isRecovering && !tab.isLoading }
    }

    /// A tab left during the loop keeps its view and its message: it does not reload when shown either.
    @Test func `a hidden page that crashed twice shows the message when shown`() async throws {
        let tab = try await openTab()
        try terminate(tab)
        try await waitForReload(of: tab, requests: 2)
        manager.newTab()
        try terminate(tab)
        #expect(tab.webView != nil)
        #expect(tab.crash.isShowingProblem)

        manager.select(tab)
        try await Task.sleep(for: .milliseconds(200))
        #expect(tab.crash.isShowingProblem)
        #expect(pages.count("page") == 2)
        tab.reload()
        try await waitForReload(of: tab, requests: 3)
    }

    /// Like waking from suspension (task 5.6): neither the automatic reload nor the one from the message is a visit,
    /// even more than a minute after the visit (an ordinary reload would be a new one).
    @Test func `a reload after a crash is not a new visit`() async throws {
        let pages = LocalTestPages()
        let container = try BrowserSchema.makeContainer(inMemory: true)
        let store = HistoryStore(container: container, now: { [clock] in clock.now })
        manager.history = HistoryScope(store: store, profileID: UUID(), spaceID: UUID())
        func visits() -> Int {
            (try? container.mainContext.fetchCount(FetchDescriptor<HistoryRecord>())) ?? -1
        }
        let tab = manager.newTab(url: pages.index)
        try await waitUntil { tab.title == LocalTestPages.indexTitle && !tab.isLoading && visits() == 1 }

        clock.advance(120)
        try terminate(tab)
        try await waitUntil { !tab.crash.isRecovering && !tab.isLoading }
        clock.advance(5)
        try terminate(tab)
        #expect(tab.crash.isShowingProblem)
        clock.advance(120)
        let finished = tab.history.finishedLoads
        tab.reload()
        try await waitUntil { !tab.crash.isRecovering && !tab.isLoading && tab.history.finishedLoads > finished }
        #expect(visits() == 1)
        #expect(tab.title == LocalTestPages.indexTitle)

        // Control: an ordinary reload, more than a minute later, is a visit.
        clock.advance(120)
        tab.reload()
        try await waitUntil { visits() == 2 }
    }
}
