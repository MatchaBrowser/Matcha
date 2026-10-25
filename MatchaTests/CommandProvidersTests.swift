import Foundation
@testable import Matcha
import Testing

/// Command bar sources for tabs, actions and history.
@MainActor
struct CommandProvidersTests {
    private let session: BrowserSession
    private let windowModel: WindowModel
    private let context = CommandContext(isPrivate: false, showsSearchSuggestions: true)

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        windowModel = WindowModel(session: session, defaults: nil)
    }

    private var shownTabs: TabManager {
        windowModel.space.tabManager
    }

    private func openTabs(in windowModel: WindowModel? = nil) async -> [CommandCandidate] {
        await OpenTabsProvider(windowModel: windowModel ?? self.windowModel).candidates(for: query("x"), context: context)
    }

    private func actions(_ context: CommandContext? = nil) -> [CommandActionID] {
        ActionsProvider(windowModel: windowModel).available(in: context ?? self.context).compactMap { candidate in
            if case let .action(action, _) = candidate.kind {
                return action
            }
            return nil
        }
    }

    private func id(_ tab: BrowserTab) -> String {
        "tab:\(tab.id.uuidString)"
    }

    // MARK: Tabs

    @Test func `lists tabs of every space with the shown space first`() async {
        let first = windowModel.space
        let firstTab = first.tabManager.newTab(url: blankPage("one"))
        windowModel.newSpace()
        let shown = windowModel.space
        let shownTab = shown.tabManager.newTab(url: blankPage("two"))
        shown.tabManager.newTab(url: blankPage("three"))

        let candidates = await openTabs()
        #expect(candidates.map(\.id) == [id(shownTab), id(firstTab)])
        #expect(candidates[0].kind == .tab(
            TabReference(tabID: shownTab.id, spaceID: shown.id), place: .today, spaceName: nil, lastActivity: shownTab.lastActivity,
        ))
        #expect(candidates[0].title == "about:blank?two")
        #expect(candidates[0].url == blankPage("two"))
        #expect(candidates[1].kind == .tab(
            TabReference(tabID: firstTab.id, spaceID: first.id), place: .today, spaceName: first.record.name,
            lastActivity: firstTab.lastActivity,
        ))
    }

    @Test func `skips the selected tab and empty tabs`() async {
        let listed = shownTabs.newTab(url: blankPage("one"))
        shownTabs.newTab()
        shownTabs.newTab(url: blankPage("selected"))
        #expect(await openTabs().map(\.id) == [id(listed)])
    }

    @Test func `other panes of the displayed split stay listed`() async {
        let first = shownTabs.newTab(url: blankPage("one"))
        let second = shownTabs.newTab(url: blankPage("two"))
        shownTabs.openInSplit(first)
        #expect(shownTabs.displayedTabs.count == 2)
        // The active pane is excluded; the other pane is still offered, to switch to it from the bar.
        #expect(await openTabs().map(\.id) == [id(second)])
    }

    @Test func `shared favorites come once from the shown space`() async {
        let shown = windowModel.space
        let favorite = shown.tabManager.newTab(url: blankPage("favorite"))
        shown.tabManager.setPlace(favorite, to: .favorite)
        shown.tabManager.newTab()
        shown.saveNow()
        let other = session.addSpace(inProfileOf: shown)
        // The profile's other Space has the same favorite tab (`ProfileFavorites`).
        #expect(other.tabManager.tab(withID: favorite.id) === favorite)

        let listed = await openTabs().filter { $0.id == id(favorite) }
        #expect(listed.count == 1)
        #expect(listed.first?.kind == .tab(
            TabReference(tabID: favorite.id, spaceID: shown.id), place: .favorite, spaceName: nil, lastActivity: favorite.lastActivity,
        ))

        // Favorite shown: it is not offered from the other Space either (going there would switch Space for the page
        // already on screen).
        shown.tabManager.select(favorite)
        #expect(windowModel.space === shown)
        #expect(await openTabs().allSatisfy { $0.id != id(favorite) })
    }

    @Test func `favorites of another profile are listed with their space name`() async {
        let work = session.addProfile(named: "Travail")
        let favorite = work.tabManager.newTab(url: blankPage("work"))
        work.tabManager.setPlace(favorite, to: .favorite)
        work.saveNow()
        session.addSpace(inProfileOf: work)

        let listed = await openTabs().filter { $0.id == id(favorite) }
        #expect(listed.count == 1)
        #expect(listed.first?.kind == .tab(
            TabReference(tabID: favorite.id, spaceID: work.id), place: .favorite, spaceName: work.record.name,
            lastActivity: favorite.lastActivity,
        ))
    }

    @Test func `an unloaded pinned tab is listed with its original address`() async throws {
        let origin = blankPage("origin")
        let pinned = shownTabs.newTab(url: origin)
        try await waitUntil { pinned.url == origin }
        shownTabs.setPlace(pinned, to: .pinned)
        pinned.load(blankPage("elsewhere"))
        shownTabs.newTab()
        shownTabs.close(pinned)
        #expect(!pinned.isLoaded)

        let candidates = await openTabs()
        #expect(candidates.map(\.id) == [id(pinned)])
        #expect(candidates.first?.url == origin)
        #expect(candidates.first?.title == "about:blank?origin")
        if case let .tab(_, place, _, _) = candidates.first?.kind {
            #expect(place == .pinned)
        } else {
            Issue.record("Onglet attendu")
        }
    }

    @Test func `a private session lists only its own tabs`() async {
        shownTabs.newTab(url: blankPage("main"))
        let privateWindow = WindowModel(session: BrowserSession.makePrivate(), defaults: nil)
        let own = privateWindow.space.tabManager.newTab(url: blankPage("private"))
        privateWindow.space.tabManager.newTab()
        #expect(await openTabs(in: privateWindow).map(\.id) == [id(own)])
    }

    // MARK: Actions

    @Test func `private windows offer no new space`() {
        #expect(actions(CommandContext(isPrivate: true, showsSearchSuggestions: true)) == [.settings])
        #expect(actions() == [.newSpace, .settings])
    }

    @Test func `copy url needs an address`() {
        #expect(actions() == [.newSpace, .settings])
        shownTabs.newTab()
        #expect(actions() == [.newSpace, .settings])
        shownTabs.newTab(url: blankPage("one"))
        #expect(actions() == [.newSpace, .copyURL, .settings])
    }

    @Test func `settings is always offered`() async {
        let privateContext = CommandContext(isPrivate: true, showsSearchSuggestions: false)
        #expect(actions(privateContext) == [.settings])
        let provider = ActionsProvider(windowModel: windowModel)
        let settings = CommandActionID.settings
        let expected = CommandCandidate(kind: .action(settings, keywords: settings.keywords), title: settings.title, url: nil)
        #expect(provider.available(in: privateContext) == [expected])
        #expect(await provider.candidates(for: query("x"), context: privateContext) == [expected])
        #expect(!settings.keywords.isEmpty)
    }

    // MARK: History

    @Test func `history maps entries and is never read in private windows`() async throws {
        let visit = fixedNow.addingTimeInterval(-3600)
        let site = try #require(URL(string: "https://www.example.com/docs/"))
        let source = FakeHistory(entries: [
            HistoryEntry(url: site, title: "Example docs", visitCount: 3, lastVisit: visit),
            HistoryEntry(url: site, title: " ", visitCount: 1, lastVisit: visit),
            HistoryEntry(url: site, title: nil, visitCount: 1, lastVisit: visit),
        ])
        let provider = HistoryProvider(source: source)

        let candidates = await provider.candidates(for: query("exa"), context: context)
        #expect(candidates.map(\.title) == ["Example docs", "example.com/docs", "example.com/docs"])
        #expect(candidates.first?.kind == .history(visitCount: 3, lastVisit: visit))
        #expect(candidates.allSatisfy { $0.url == site })
        #expect(source.requests.map(\.text) == ["exa"])
        #expect(source.requests.map(\.limit) == [HistoryProvider.fetchLimit])

        let privateContext = CommandContext(isPrivate: true, showsSearchSuggestions: true)
        #expect(await provider.candidates(for: query("exa"), context: privateContext).isEmpty)
        #expect(source.requests.count == 1)
    }

    @Test func `no history source gives nothing`() async {
        #expect(await HistoryProvider(source: nil).candidates(for: query("exa"), context: context).isEmpty)
    }
}
