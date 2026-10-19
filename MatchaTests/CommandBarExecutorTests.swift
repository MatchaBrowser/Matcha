import AppKit
import Foundation
@testable import Matcha
import Testing

/// Effects of the command bar rows on tabs and Spaces.
@MainActor
struct CommandBarExecutorTests {
    private let session: BrowserSession
    private let windowModel: WindowModel
    private let model: CommandBarModel
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-\(UUID().uuidString)"))
    private let settings = CommandBarSettings(searchEngine: .google, newTabPage: .blank, homePage: "", showsSearchSuggestions: false)

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        windowModel = WindowModel(session: session, defaults: nil)
        model = CommandBarModel(windowModel: windowModel, suggestions: FakeSuggestionEngine().provider())
    }

    private var tabManager: TabManager {
        windowModel.space.tabManager
    }

    private func executor(openSettings: @escaping () -> Void = {}) -> CommandBarExecutor {
        var executor = CommandBarExecutor(model: model, window: nil, openSettings: openSettings)
        executor.pasteboard = pasteboard
        executor.animate = { $0() }
        return executor
    }

    @Test func `new tab mode opens the url in a new selected tab`() {
        let existing = tabManager.newTab(url: blankPage("one"))
        model.newTab(settings)
        model.updateText("about:blank?two")
        executor().submit(nil)
        #expect(!model.isPresented)
        #expect(tabManager.tabs.count == 2)
        let opened = tabManager.selectedTab
        #expect(opened !== existing)
        #expect(opened?.url == blankPage("two"))
        #expect(tabManager.todayTabs.first === opened)
    }

    @Test func `current tab mode loads in the target tab`() async throws {
        let target = tabManager.newTab(url: blankPage("one"))
        tabManager.setPlace(target, to: .pinned)
        let other = tabManager.newTab(url: blankPage("two"))
        let url = blankPage("three")
        let focused = executor().perform(.run(.open(url), mode: .currentTab(target.id)))
        #expect(focused === target)
        #expect(tabManager.tabs.count == 2)
        #expect(tabManager.selectedTab === target)
        #expect(tabManager.place(of: target) == .pinned)
        try await waitUntil { target.url == url }
        #expect(other.url == blankPage("two"))
    }

    @Test func `a vanished target falls back to a new tab`() {
        let existing = tabManager.newTab(url: blankPage("one"))
        let url = blankPage("two")
        let focused = executor().perform(.run(.open(url), mode: .currentTab(UUID())))
        #expect(tabManager.tabs.count == 2)
        #expect(focused !== existing)
        #expect(focused === tabManager.selectedTab)
        #expect(focused?.url == url)
    }

    @Test func `switching to a tab of the shown space selects it`() {
        let first = tabManager.newTab(url: blankPage("one"))
        tabManager.newTab(url: blankPage("two"))
        let reference = TabReference(tabID: first.id, spaceID: windowModel.space.id)
        let focused = executor().perform(.run(.switchToTab(reference), mode: .newTab))
        #expect(focused === first)
        #expect(tabManager.selectedTab === first)
        #expect(tabManager.tabs.count == 2)
    }

    @Test func `switching to a tab of another space shows that space with the tab selected`() {
        let shown = windowModel.space
        let other = session.addSpace(inProfileOf: shown)
        let wanted = other.tabManager.newTab(url: blankPage("one"))
        other.tabManager.newTab(url: blankPage("two"))
        var animations = 0
        var executor = executor()
        executor.animate = { change in
            animations += 1
            change()
        }
        let focused = executor.perform(.run(.switchToTab(TabReference(tabID: wanted.id, spaceID: other.id)), mode: .newTab))
        #expect(focused === wanted)
        #expect(windowModel.space === other)
        #expect(other.tabManager.selectedTab === wanted)
        #expect(animations == 1)
    }

    @Test func `a missing tab changes nothing`() {
        let selected = tabManager.newTab(url: blankPage("one"))
        let shown = windowModel.space
        let missing = [
            TabReference(tabID: UUID(), spaceID: shown.id),
            TabReference(tabID: selected.id, spaceID: UUID()),
        ]
        for reference in missing {
            let focused = executor().perform(.run(.switchToTab(reference), mode: .newTab))
            #expect(focused === selected)
        }
        #expect(windowModel.space === shown)
        #expect(tabManager.selectedTab === selected)
        #expect(tabManager.tabs.count == 1)
    }

    @Test func `empty submission opens an empty tab`() {
        model.newTab(settings)
        #expect(model.submission(for: nil) == .openEmptyTab)
        executor().submit(nil)
        #expect(!model.isPresented)
        #expect(tabManager.tabs.count == 1)
        #expect(tabManager.selectedTab?.url == nil)
        #expect(executor().perform(.openEmptyTab) == nil)
        #expect(tabManager.tabs.count == 2)
    }

    @Test func `new space action adds and shows a space`() {
        let focused = executor().perform(.run(.perform(.newSpace), mode: .newTab))
        #expect(focused == nil)
        #expect(session.spaces.count == 2)
        #expect(windowModel.space === session.spaces[1])
    }

    @Test func `copy url writes the pasteboard and shows the confirmation`() {
        defer { pasteboard.releaseGlobally() }
        let tab = tabManager.newTab(url: blankPage("one"))
        let focused = executor().perform(.run(.perform(.copyURL), mode: .currentTab(tab.id)))
        #expect(focused === tab)
        #expect(pasteboard.string(forType: .string) == "about:blank?one")
        // Same confirmation as ⇧⌘C.
        #expect(windowModel.copyConfirmation.isVisible)
        #expect(windowModel.copyConfirmation.presentationCount == 1)
    }

    @Test func `settings action calls open settings once`() {
        var calls = 0
        let focused = executor { calls += 1 }.perform(.run(.perform(.settings), mode: .newTab))
        #expect(focused == nil)
        #expect(calls == 1)
    }

    @Test func `submit closes the bar before running`() async throws {
        var presentedDuringAction: [Bool] = []
        let executor = executor { presentedDuringAction.append(model.isPresented) }
        model.newTab(settings)
        model.updateText(CommandActionID.settings.title)
        await model.waitForPendingResults()
        let row = try #require(model.rows.first { $0.target == .perform(.settings) })
        executor.submit(row.id)
        #expect(presentedDuringAction == [false])
        #expect(!model.isPresented)

        // Nothing to run: the bar stays open.
        tabManager.newTab()
        model.editCurrentTab(settings)
        executor.submit(nil)
        #expect(model.isPresented)
    }
}
