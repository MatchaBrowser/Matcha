import Foundation
@testable import Matcha
import SwiftData
import Testing

/// History of a page waking from suspension (task 5.6): only the reload of the same address is skipped.
@MainActor
struct PageHistoryResumeTests {
    private let container: ModelContainer
    private let scope: HistoryScope

    init() throws {
        container = try BrowserSchema.makeContainer(inMemory: true)
        scope = HistoryScope(store: HistoryStore(container: container), profileID: UUID(), spaceID: UUID())
    }

    private var visits: Int {
        (try? container.mainContext.fetchCount(FetchDescriptor<HistoryRecord>())) ?? -1
    }

    @Test func `only the first load of the resumed address is skipped`() throws {
        let history = PageHistory()
        let page = try #require(URL(string: "https://example.com/page"))
        history.pageWillResume(url: page)
        // Same address, fragment ignored: skipped.
        history.pageDidFinishLoading(url: URL(string: "https://example.com/page#haut"), title: "Page", scope: scope)
        #expect(visits == 0)
        history.pageDidFinishLoading(url: page, title: "Page", scope: scope)
        #expect(visits == 1)
    }

    @Test func `another address loaded first is a visit`() {
        let history = PageHistory()
        history.pageWillResume(url: URL(string: "https://example.com/page"))
        history.pageDidFinishLoading(url: URL(string: "https://example.com/other"), title: "Autre", scope: scope)
        #expect(visits == 1)
    }

    @Test func `a failed reload forgets the skip`() throws {
        let history = PageHistory()
        let page = try #require(URL(string: "https://example.com/page"))
        history.pageWillResume(url: page)
        history.navigationDidFail()
        history.pageDidFinishLoading(url: page, title: "Page", scope: scope)
        #expect(visits == 1)
    }
}
