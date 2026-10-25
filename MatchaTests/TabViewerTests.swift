import Foundation
@testable import Matcha
import Testing
import WebKit

/// Several windows on one Space (`TabViewer`): each has its selection, a page is shown by one window only.
@MainActor
struct TabViewerTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Two windows on screen, opened one after the other: the first takes the initial viewer, the second a new one.
    private func twoWindows() -> (first: TabViewer, second: TabViewer) {
        let first = manager.makeViewer()
        manager.setOnScreen(first, true)
        let second = manager.makeViewer()
        manager.setOnScreen(second, true)
        return (first, second)
    }

    @Test func `the first window takes the restored selection`() {
        let tab = manager.newTab()
        let viewer = manager.makeViewer()
        #expect(viewer === manager.activeViewer)
        #expect(viewer.selectedTabID == tab.id)
    }

    @Test func `a second window starts empty when the first shows the tab`() {
        manager.newTab()
        let (_, second) = twoWindows()
        #expect(second.selectedTabID == nil)
    }

    @Test func `each window keeps its own selection and actions follow the active one`() {
        let (first, second) = twoWindows()
        let one = manager.newTab()
        manager.activate(second)
        let two = manager.newTab()
        #expect(first.selectedTabID == one.id)
        #expect(second.selectedTabID == two.id)
        #expect(manager.selectedTab === two)
        manager.activate(first)
        #expect(manager.selectedTab === one)
        #expect(manager.selectedTab(in: second) === two)
    }

    @Test func `the last window that shows a tab gets its page, the other one can take it back`() {
        let (first, second) = twoWindows()
        let tab = manager.newTab()
        #expect(manager.shows(tab.id, in: first))
        manager.activate(second)
        manager.select(tab)
        #expect(manager.shows(tab.id, in: second))
        #expect(!manager.shows(tab.id, in: first))
        manager.showHere(first)
        #expect(manager.shows(tab.id, in: first))
        #expect(!manager.shows(tab.id, in: second))
    }

    @Test func `a window that leaves a tab gives its page to the other window showing it`() {
        let (first, second) = twoWindows()
        let tab = manager.newTab()
        let other = manager.newTab(select: false)
        manager.activate(second)
        manager.select(tab)
        #expect(!manager.shows(tab.id, in: first))
        manager.select(other)
        #expect(manager.shows(tab.id, in: first))
    }

    @Test func `closing a tab moves the selection of every window showing it`() {
        let (first, second) = twoWindows()
        let below = manager.newTab()
        let tab = manager.newTab()
        manager.activate(second)
        manager.select(tab)
        manager.close(tab)
        #expect(first.selectedTabID == below.id)
        #expect(second.selectedTabID == below.id)
    }

    @Test func `clearing the today tabs empties every window that showed one`() {
        let (first, second) = twoWindows()
        let tab = manager.newTab()
        manager.activate(second)
        manager.select(tab)
        manager.clearToday()
        #expect(first.selectedTabID == nil)
        #expect(second.selectedTabID == nil)
    }

    @Test func `a window leaving a tab shows the next one without changing the others`() {
        let (first, second) = twoWindows()
        let below = manager.newTab()
        let tab = manager.newTab()
        manager.activate(second)
        manager.select(tab)
        manager.moveSelection(of: second, awayFrom: [tab.id])
        #expect(second.selectedTabID == below.id)
        #expect(first.selectedTabID == tab.id)
    }

    @Test func `the last closed window leaves its selection to the next one`() {
        let tab = manager.newTab()
        let viewer = manager.makeViewer()
        manager.setOnScreen(viewer, true)
        manager.releaseViewer(viewer)
        #expect(manager.viewers.all.count == 1)
        let next = manager.makeViewer()
        #expect(next === viewer)
        #expect(next.selectedTabID == tab.id)
    }

    @Test func `a closed window among others is forgotten and the active one goes to a window on screen`() {
        let (first, second) = twoWindows()
        manager.activate(second)
        manager.releaseViewer(second)
        #expect(manager.viewers.all.count == 1)
        #expect(manager.activeViewer === first)
    }

    @Test func `a window hiding the Space gives the actions to another window showing it`() {
        let (first, second) = twoWindows()
        manager.activate(second)
        manager.setOnScreen(second, false)
        #expect(manager.activeViewer === first)
    }

    @Test func `a page acting opens its link in its own window`() throws {
        let (first, second) = twoWindows()
        let source = manager.newTab()
        manager.activate(second)
        let webView = try #require(source.webView)
        let configuration = manager.pages.makeConfiguration(websiteDataStore: manager.websiteDataStore)
        try manager.openLink(#require(URL(string: "about:blank")), configuration: configuration, from: webView, inBackground: false)
        #expect(first.selectedTabID != source.id)
        #expect(second.selectedTabID == nil)
        #expect(manager.activeViewer === second)
    }

    @Test func `the peek of a window stays open when another window changes tab`() throws {
        let (first, second) = twoWindows()
        let source = manager.newTab()
        manager.activate(second)
        let other = manager.newTab()
        let peek = try manager.openPeek(#require(URL(string: "about:blank")), from: source)
        #expect(peek != nil)
        #expect(manager.peek(in: first) != nil)
        #expect(manager.peek(in: second) == nil)
        manager.select(other)
        #expect(manager.peek != nil)
        manager.activate(first)
        manager.select(other)
        #expect(manager.peek == nil)
    }
}
