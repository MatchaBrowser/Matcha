import AppKit
import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Tabs going between a window of its own tabs and the Spaces: drag and drop between sidebars, command bar.
@MainActor
struct WindowTabsTransferTests {
    private let session: BrowserSession
    private let first: WindowModel

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        first = WindowModel(session: session, defaults: nil)
        first.windowDidAppear()
    }

    private var space: SpaceSession {
        session.spaces[0]
    }

    /// A window of its own tabs holding `tab`, displayed.
    private func detachedWindow(with tab: BrowserTab) -> WindowModel {
        let state = first.detachToNewWindow(tab)
        let window = WindowModels(session: session, spaceID: state.spaceID, windowTabsID: state.windowTabsID).window
        window.windowDidAppear()
        return window
    }

    // MARK: Drag and drop

    @Test func `a tab dropped from a Space into a window of its own tabs leaves the Space`() {
        let tab = space.tabManager.newTab(url: blankPage("one"))
        let other = space.tabManager.newTab(url: blankPage("two"))
        let window = detachedWindow(with: tab)
        let webView = other.webView
        let brought = session.bringTab(other.id, into: window.tabManager)
        #expect(brought === other)
        #expect(other.webView === webView)
        #expect(space.tabManager.tab(withID: other.id) == nil)
        #expect(window.tabManager.tabs.count == 2)
    }

    @Test func `a tab dropped from a window of its own tabs into a Space leaves the window`() {
        let tab = space.tabManager.newTab(url: blankPage("one"))
        let window = detachedWindow(with: tab)
        let brought = session.bringTab(tab.id, into: space.tabManager)
        #expect(brought === tab)
        #expect(space.tabManager.place(of: tab) == .today)
        #expect(window.hasNoOwnTabsLeft)
    }

    @Test func `a pinned tab dropped into a window of its own tabs stays pinned and the window gets a copy`() {
        let anchor = space.tabManager.newTab(url: blankPage("one"))
        let pinned = space.tabManager.newTab(url: blankPage("two"))
        space.tabManager.setPlace(pinned, to: .pinned)
        let window = detachedWindow(with: anchor)
        let brought = session.bringTab(pinned.id, into: window.tabManager)
        #expect(brought !== pinned)
        #expect(space.tabManager.place(of: pinned) == .pinned)
        #expect(window.tabManager.tabs.count == 2)
    }

    @Test func `a tab unknown to the other windows is not brought`() {
        #expect(session.bringTab(UUID(), into: space.tabManager) == nil)
    }

    // MARK: Command bar

    @Test func `a window of its own tabs lists them, then the tabs of the Spaces`() {
        let inSpace = space.tabManager.newTab(url: blankPage("one"))
        let tab = space.tabManager.newTab(url: blankPage("two"))
        let window = detachedWindow(with: tab)
        window.activate()
        let own = window.tabManager.newTab(url: blankPage("three"))
        window.tabManager.select(tab)
        let candidates = OpenTabsProvider(windowModel: window).openTabs()
        let references = candidates.compactMap { candidate -> TabReference? in
            if case let .tab(reference, _, _, _) = candidate.kind {
                return reference
            }
            return nil
        }
        #expect(references.map(\.tabID) == [own.id, inSpace.id])
        #expect(references.first?.spaceID == window.windowTabs?.id)
    }

    @Test func `a Space window lists the tabs of the windows of their own tabs`() {
        let tab = space.tabManager.newTab(url: blankPage("one"))
        _ = detachedWindow(with: tab)
        let ids = OpenTabsProvider(windowModel: first).openTabs().map(\.id)
        #expect(ids.contains("tab:\(tab.id.uuidString)"))
    }

    @Test func `switching to a tab of another window of its own tabs selects it there and brings it forward`() {
        let tab = space.tabManager.newTab(url: blankPage("one"))
        let window = detachedWindow(with: tab)
        window.activate()
        window.tabManager.newTab(url: blankPage("two"))
        var broughtForward = 0
        window.windowTabs?.bringWindowToFront = { broughtForward += 1 }
        let model = CommandBarModel(windowModel: first, suggestions: FakeSuggestionEngine().provider())
        let executor = CommandBarExecutor(model: model, window: nil, openSettings: {})
        let reference = TabReference(tabID: tab.id, spaceID: window.windowTabs?.id ?? UUID())
        #expect(executor.perform(.run(.switchToTab(reference), mode: .newTab)) === tab)
        #expect(window.selectedTab === tab)
        #expect(broughtForward == 1)
    }

    @Test func `switching to a Space tab from a window of its own tabs shows it in the main window`() {
        let wanted = space.tabManager.newTab(url: blankPage("one"))
        let tab = space.tabManager.newTab(url: blankPage("two"))
        let window = detachedWindow(with: tab)
        var revealed: [BrowserTab] = []
        let model = CommandBarModel(windowModel: window, suggestions: FakeSuggestionEngine().provider())
        var executor = CommandBarExecutor(model: model, window: nil, openSettings: {})
        executor.revealInSpace = { tab, _ in revealed.append(tab) }
        let reference = TabReference(tabID: wanted.id, spaceID: space.id)
        executor.perform(.run(.switchToTab(reference), mode: .newTab))
        #expect(revealed.map(\.id) == [wanted.id])
        #expect(window.windowTabs != nil)
    }

    /// Review ON12: a pinned tab dropped into the pinned tabs of another Space keeps its original address.
    @Test func `a pinned tab dropped into another Space's pinned tabs keeps its original address`() {
        let origin = space.tabManager.newTab(url: blankPage("elsewhere"))
        space.tabManager.setPlace(origin, to: .pinned)
        // Pinned on another page, then the tab went elsewhere.
        let pinnedURL = blankPage("origin")
        origin.pinnedURL = pinnedURL
        let other = session.addSpace(inProfileOf: space)
        let brought = session.bringTab(origin.id, into: other.tabManager, at: .pinned(folder: nil, index: 0))
        #expect(brought === origin)
        #expect(other.tabManager.place(of: origin) == .pinned)
        #expect(origin.pinnedURL == pinnedURL)
        #expect(space.tabManager.tab(withID: origin.id) == nil)
    }

    /// Review ON6: one rule for what moves, what is copied and what is recreated.
    @Test(arguments: [
        (true, TabPlace.today, false, TabTransferPlan.move),
        (true, .pinned, false, .move),
        (true, .favorite, true, .copy),
        (true, .today, true, .move),
        (false, .today, false, .recreate(keepsSource: false)),
        (false, .pinned, true, .recreate(keepsSource: true)),
    ])
    func `a transfer moves, copies or recreates the tab`(sameProfile: Bool, place: TabPlace, intoWindowTabs: Bool, plan: TabTransferPlan) {
        #expect(TabTransferPlan.plan(sameProfile: sameProfile, sourcePlace: place, intoWindowTabs: intoWindowTabs) == plan)
    }

    /// Review ON7: until their window closes, the tabs of a window of its own tabs are saved with their Space.
    @Test func `the tabs of a window of its own tabs are saved with their Space until it closes`() throws {
        let tab = space.tabManager.newTab(url: blankPage("detached"))
        let window = detachedWindow(with: tab)
        session.saveAll()
        let record = try #require(try session.container.mainContext.fetch(FetchDescriptor<TabRecord>()).first { $0.id == tab.id })
        #expect(record.place == .today && record.space?.id == space.id)
        window.windowDidClose()
        session.saveAll()
        #expect(try session.container.mainContext.fetch(FetchDescriptor<TabRecord>()).allSatisfy { $0.id != tab.id })
    }

    /// Review ON8: deleting a profile closes its windows of their own tabs before its data is erased.
    @Test func `deleting a profile closes its windows of their own tabs`() throws {
        let work = session.addProfile(named: "Work")
        let windowModel = WindowModel(session: session, defaults: nil, spaceID: work.id)
        windowModel.windowDidAppear()
        let tab = work.tabManager.newTab(url: blankPage("work"))
        let state = windowModel.detachToNewWindow(tab)
        var closed = false
        let tabs = try #require(session.windowTabs(withID: state.windowTabsID))
        tabs.closeWindow = { closed = true }
        let profile = try #require(work.record.profile)
        #expect(session.removeProfile(profile) != nil)
        #expect(session.windowTabs.isEmpty)
        #expect(closed)
        #expect(!tab.isLoaded)
    }
}
