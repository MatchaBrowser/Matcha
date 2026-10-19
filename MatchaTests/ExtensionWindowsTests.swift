import Foundation
@testable import Matcha
import Testing
import WebKit

/// Events given to the extension controller when tabs, Spaces and windows change (task 6.3).
@MainActor
struct ExtensionWindowsTests {
    private let session: BrowserSession
    private let model: WindowModel
    private let sink = FakeExtensionSink()
    private let windows: ExtensionWindows
    private let windowID: UUID

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        model = WindowModel(session: session, defaults: nil)
        windows = ExtensionWindows(sink: sink)
        windows.windowDidAppear(model, window: nil)
        windows.update()
        windowID = try #require(windows.adapter(for: model)?.windowID)
    }

    private var tabManager: TabManager {
        model.space.tabManager
    }

    /// Events produced by `change`.
    private func events(after change: () -> Void) -> [FakeExtensionSink.Event] {
        _ = sink.take()
        change()
        return flush()
    }

    /// Events of the changes made since the last read.
    private func flush() -> [FakeExtensionSink.Event] {
        windows.update()
        return sink.take()
    }

    @Test func `the browser window opens once`() {
        windows.windowDidAppear(model, window: nil)
        windows.update()
        #expect(sink.take() == [.openWindow(windowID), .focusWindow(nil)])
    }

    @Test func `opening, selecting and closing tabs`() {
        _ = sink.take()
        let first = tabManager.newTab()
        #expect(flush() == [.openTab(first.id), .activateTab(first.id, previous: nil)])
        let second = tabManager.newTab(select: false)
        #expect(flush() == [.openTab(second.id)])
        #expect(events { tabManager.select(second) } == [.activateTab(second.id, previous: first.id)])
        #expect(events { tabManager.close(second) } == [
            .activateTab(first.id, previous: second.id),
            .closeTab(second.id, windowIsClosing: false),
        ])
    }

    @Test func `changes in the same turn are grouped`() {
        let first = tabManager.newTab()
        windows.update()
        _ = sink.take()
        let second = tabManager.newTab()
        tabManager.close(first)
        windows.update()
        #expect(sink.take() == [
            .openTab(second.id),
            .activateTab(second.id, previous: first.id),
            .closeTab(first.id, windowIsClosing: false),
        ])
    }

    @Test func `switching Space only changes the active tab`() {
        let home = model.space
        let first = tabManager.newTab()
        model.newSpace()
        let second = tabManager.newTab()
        windows.update()
        _ = sink.take()
        #expect(windows.tabs(inWindow: windowID).map(\.tabID) == [first.id, second.id])
        #expect(events { model.select(home) } == [.activateTab(first.id, previous: second.id)])
    }

    @Test func `a tab sent to another Space moves within the window`() {
        let home = model.space
        let kept = [tabManager.newTab(select: false), tabManager.newTab(select: false)]
        let moved = tabManager.newTab()
        model.newSpace()
        let other = model.space
        _ = tabManager.newTab()
        model.select(home)
        windows.update()
        #expect(windows.location(ofTab: moved.id)?.index == 0)
        let changes = events { model.move(moved, to: other) }
        #expect(changes.contains(.moveTab(moved.id, from: 0, window: windowID)))
        #expect(!changes.contains {
            if case .closeTab = $0 {
                true
            } else {
                false
            }
        })
        #expect(Array(windows.tabs(inWindow: windowID).map(\.tabID).prefix(3)) == kept.reversed().map(\.id) + [moved.id])
    }

    @Test func `split panes are selected, separating deselects them`() throws {
        let left = tabManager.newTab()
        let right = tabManager.newTab(select: false)
        windows.update()
        _ = sink.take()
        // New tab at the top of today tabs: it moves to the right of the other one.
        #expect(events { tabManager.openInSplit(right) } == [
            .moveTab(right.id, from: 0, window: windowID),
            .activateTab(right.id, previous: left.id),
        ])
        #expect(windows.isSelected(left.id))
        #expect(windows.isSelected(right.id))
        let group = try #require(tabManager.displayedSplit)
        #expect(events { tabManager.separateSplit(group.id) } == [.deselectTabs([left.id])])
    }

    @Test func `pinning a tab changes its pinned property`() {
        let tab = tabManager.newTab()
        windows.update()
        _ = sink.take()
        #expect(events { tabManager.setPlace(tab, to: .pinned) } == [.changeTab(tab.id, .pinned)])
    }

    @Test func `a page title and address are tab properties`() async throws {
        let tab = tabManager.newTab()
        windows.update()
        _ = sink.take()
        try tab.load(#require(URL(string: "about:blank")))
        try await waitUntil { tab.url != nil && !tab.isLoading }
        windows.update()
        let changes = sink.take().compactMap { event -> WKWebExtension.TabChangedProperties? in
            if case let .changeTab(id, properties) = event, id == tab.id {
                properties
            } else {
                nil
            }
        }
        #expect(changes.contains { $0.contains(.URL) })
    }

    @Test func `the peek is the active tab while it is open`() throws {
        let source = tabManager.newTab()
        _ = flush()
        let url = try #require(URL(string: "about:blank"))
        let peek = try #require(tabManager.openPeek(url, from: source))
        #expect(flush() == [.openTab(peek.tab.id), .activateTab(peek.tab.id, previous: source.id)])
        #expect(windows.tabs(inWindow: windowID).map(\.tabID) == [source.id, peek.tab.id])
        #expect(events { tabManager.closePeek() } == [
            .activateTab(source.id, previous: peek.tab.id),
            .closeTab(peek.tab.id, windowIsClosing: false),
        ])
        let kept = try #require(tabManager.openPeek(url, from: source))
        _ = flush()
        // Opened as a tab, it keeps its place and stays active; its original tab is no longer selected.
        #expect(events { tabManager.openPeekAsTab() } == [.deselectTabs([source.id])])
        #expect(windows.tabs(inWindow: windowID).map(\.tabID) == [source.id, kept.tab.id])
    }

    @Test func `a mini window is a popup window of one page`() {
        let miniWindows = MiniWindowManager.forTests(session: session)
        windows.miniWindows = miniWindows
        windows.update()
        _ = sink.take()
        let mini = miniWindows.openNew(source: .menu)
        #expect(flush() == [.openWindow(mini.id), .activateTab(mini.tab.id, previous: nil), .focusWindow(nil)])
        let window = windows.windowAdapter(mini.id)
        #expect(window.type == .popup)
        #expect(!window.isPrivate)
        #expect(events { mini.close() } == [.closeTab(mini.tab.id, windowIsClosing: true), .closeWindow(mini.id)])
    }

    @Test func `a mini window page sent to a Space moves into the browser window`() async throws {
        let miniWindows = MiniWindowManager.forTests(session: session)
        miniWindows.setMainWindow(FakeMainWindowLink(windowModel: model))
        windows.miniWindows = miniWindows
        let mini = miniWindows.openNew(loading: TestPages.url("page"), source: .menu)
        try await waitUntil { mini.tab.url != nil && !mini.tab.isLoading }
        windows.update()
        _ = sink.take()
        miniWindows.openInSpace(mini) {}
        windows.update()
        let changes = sink.take()
        #expect(changes.first == .moveTab(mini.tab.id, from: 0, window: mini.id))
        #expect(changes.contains(.closeWindow(mini.id)))
        #expect(!changes.contains(.closeTab(mini.tab.id, windowIsClosing: true)))
        #expect(windows.location(ofTab: mini.tab.id)?.windowID == windowID)
    }

    @Test func `a closed browser window closes its tabs`() {
        let tab = tabManager.newTab()
        windows.update()
        _ = sink.take()
        #expect(events { windows.windowDidDisappear(model) } == [.closeTab(tab.id, windowIsClosing: true), .closeWindow(windowID)])
    }

    @Test func `a private window is private`() throws {
        let privateSession = BrowserSession.makePrivate()
        let privateModel = WindowModel(session: privateSession, defaults: nil)
        windows.windowDidAppear(privateModel, window: nil)
        windows.update()
        let window = try #require(windows.adapter(for: privateModel))
        #expect(window.isPrivate)
        #expect(windows.adapter(for: model)?.isPrivate == false)
    }

    /// Audit C5: nothing is followed without a loaded extension; the next one to load reads the windows afresh, without
    /// receiving the changes made before it.
    @Test func `without a loaded extension nothing is followed`() {
        _ = sink.take()
        sink.isListening = false
        windows.update()
        let tab = tabManager.newTab()
        windows.update()
        #expect(sink.take().isEmpty)
        #expect(windows.location(ofTab: tab.id) == nil)

        windows.update(beforeLoading: true)
        #expect(windows.location(ofTab: tab.id)?.windowID == windowID)
        #expect(sink.take().isEmpty)
        sink.isListening = true
        let next = tabManager.newTab()
        windows.update()
        #expect(sink.take().contains(.openTab(next.id)))
    }

    @Test func `changes are seen without an explicit update`() async throws {
        _ = sink.take()
        let tab = tabManager.newTab()
        try await waitUntil { sink.events.contains(.openTab(tab.id)) }
    }
}
