import Foundation
@testable import Matcha
import Testing

struct ExtensionEventPlannerTests {
    private typealias State = ExtensionBrowserState
    private let window = UUID()
    private let other = UUID()
    private let one = UUID()
    private let two = UUID()
    private let three = UUID()
    private let four = UUID()

    private func state(_ windows: [State.Window], focused: UUID? = nil, tabs: [UUID: State.Tab]? = nil) -> State {
        let ids = windows.flatMap(\.tabIDs)
        return State(
            windows: windows,
            tabs: tabs ?? Dictionary(ids.map { ($0, State.Tab()) }) { first, _ in first },
            focusedWindowID: focused,
        )
    }

    private func browser(_ tabIDs: [UUID], active: UUID? = nil, selected: Set<UUID>? = nil, id: UUID? = nil) -> State.Window {
        State.Window(id: id ?? window, tabIDs: tabIDs, activeTabID: active, selectedTabIDs: selected ?? Set(active.map { [$0] } ?? []))
    }

    @Test func `nothing changes, nothing is sent`() {
        let current = state([browser([one, two], active: one)], focused: window)
        #expect(ExtensionEventPlanner.events(from: current, to: current).isEmpty)
    }

    @Test func `a new window opens, then takes the focus`() {
        let events = ExtensionEventPlanner.events(from: State(), to: state([browser([one], active: one)], focused: window))
        #expect(events == [.openWindow(window), .activateTab(one, previousTabID: nil), .focusWindow(window)])
    }

    @Test func `an opened and selected tab is opened, then activated`() {
        let before = state([browser([one], active: one)])
        let after = state([browser([two, one], active: two)])
        #expect(ExtensionEventPlanner.events(from: before, to: after) == [.openTab(two), .activateTab(two, previousTabID: one)])
    }

    @Test func `closing the active tab activates its neighbour before closing it`() {
        let before = state([browser([one, two], active: one)])
        let after = state([browser([two], active: two)])
        #expect(ExtensionEventPlanner.events(from: before, to: after) == [
            .activateTab(two, previousTabID: one),
            .closeTab(one, windowIsClosing: false),
        ])
    }

    @Test func `a tab moved within its window is the only one reported`() {
        let before = state([browser([one, two, three, four], active: one)])
        let after = state([browser([two, three, one, four], active: one)])
        #expect(ExtensionEventPlanner.events(from: before, to: after) == [.moveTab(one, fromIndex: 0, oldWindowID: window)])
    }

    @Test func `tabs shifted by an insertion or a removal are not moves`() {
        let before = state([browser([one, two, three], active: one)])
        let after = state([browser([four, one, three], active: one)])
        #expect(ExtensionEventPlanner.events(from: before, to: after) == [.openTab(four), .closeTab(two, windowIsClosing: false)])
    }

    @Test func `a tab moved to another window, which then closes`() {
        let before = state([browser([one], active: one), browser([two], active: two, id: other)], focused: other)
        let after = state([browser([two, one], active: two)], focused: window)
        #expect(ExtensionEventPlanner.events(from: before, to: after) == [
            .moveTab(two, fromIndex: 0, oldWindowID: other),
            .activateTab(two, previousTabID: one),
            .closeWindow(other),
            .focusWindow(window),
        ])
    }

    @Test func `a closing window closes its own tabs first`() {
        let before = state([browser([one], active: one), browser([two, three], active: two, id: other)], focused: other)
        let after = state([browser([one], active: one)])
        #expect(ExtensionEventPlanner.events(from: before, to: after) == [
            .closeTab(two, windowIsClosing: true),
            .closeTab(three, windowIsClosing: true),
            .closeWindow(other),
            .focusWindow(nil),
        ])
    }

    @Test func `split panes are selected and deselected without a new active tab`() {
        let before = state([browser([one, two, three], active: one)])
        let joined = state([browser([one, two, three], active: one, selected: [one, two])])
        #expect(ExtensionEventPlanner.events(from: before, to: joined) == [.selectTabs([two])])
        #expect(ExtensionEventPlanner.events(from: joined, to: before) == [.deselectTabs([two])])
    }

    @Test func `a new active tab is enough when the selection changes with it`() {
        let before = state([browser([one, two, three], active: one)])
        let after = state([browser([one, two, three], active: three, selected: [two, three])])
        #expect(ExtensionEventPlanner.events(from: before, to: after) == [.activateTab(three, previousTabID: one)])
    }

    @Test func `property changes are grouped by tab`() {
        let before = state([browser([one, two], active: one)])
        var tabs = before.tabs
        tabs[one] = State.Tab(title: "Titre", url: URL(string: "https://example.com"), isLoading: true)
        tabs[two] = State.Tab(isPlayingAudio: true, isPinned: true, zoomFactor: 1.25)
        let after = state([browser([one, two], active: one)], tabs: tabs)
        #expect(ExtensionEventPlanner.events(from: before, to: after) == [
            .changeTab(one, [.title, .url, .loading]),
            .changeTab(two, [.playingAudio, .pinned, .zoomFactor]),
        ])
    }

    @Test func `focus moves without other events`() {
        let before = state([browser([one], active: one), browser([two], active: two, id: other)], focused: window)
        let after = state([browser([one], active: one), browser([two], active: two, id: other)], focused: other)
        #expect(ExtensionEventPlanner.events(from: before, to: after) == [.focusWindow(other)])
    }

    @Test func `an active tab that disappears without replacement sends nothing for activation`() {
        let before = state([browser([one, two], active: one)])
        let after = state([browser([one, two], active: nil)])
        #expect(ExtensionEventPlanner.events(from: before, to: after) == [.deselectTabs([one])])
    }

    @Test func `moved elements are the ones the smallest difference moves`() {
        #expect(ExtensionEventPlanner.movedElements(from: [one, two, three], to: [one, two, three]).isEmpty)
        #expect(ExtensionEventPlanner.movedElements(from: [one, two, three, four], to: [four, one, two, three]) == [four])
    }
}
