import AppKit
import Foundation
@testable import Matcha
import Testing

/// Which browsing window acts for the app: questions of sync (review ON23), reopening from a mini window (review ON24),
/// leaving for a window of its own and closing (review ON18).
@MainActor
struct MainWindowChoiceTests {
    private let session: BrowserSession
    private let manager: MiniWindowManager

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        manager = .forTests(session: session)
    }

    private func window() -> WindowModel {
        let model = WindowModel(session: session, defaults: nil)
        model.windowDidAppear()
        return model
    }

    // MARK: Questions of sync (ON23)

    @Test func `only the last active window asks the questions of sync`() {
        let first = window()
        let second = window()
        manager.linkMainWindow(FakeMainWindowLink(windowModel: first))
        manager.linkMainWindow(FakeMainWindowLink(windowModel: second))
        #expect(manager.asksSyncQuestions(in: second))
        #expect(!manager.asksSyncQuestions(in: first))
        manager.linkMainWindow(FakeMainWindowLink(windowModel: first))
        #expect(manager.asksSyncQuestions(in: first))
        #expect(!manager.asksSyncQuestions(in: second))
        // Closed, it leaves the questions to the other.
        manager.unlinkMainWindow(first)
        #expect(manager.asksSyncQuestions(in: second))
    }

    @Test func `a private window never asks the questions of sync`() {
        let privateWindow = WindowModel(session: BrowserSession.makePrivate(), defaults: nil)
        manager.linkMainWindow(FakeMainWindowLink(windowModel: privateWindow))
        #expect(!manager.asksSyncQuestions(in: privateWindow))
    }

    // MARK: Reopening from a mini window (ON24)

    @Test func `the main window reopens through a browsing window's scene, otherwise the fallback`() {
        var scene = 0
        var fallback = 0
        manager.reopenMainWindow { fallback += 1 }
        #expect(fallback == 1)
        manager.openMainWindow = { scene += 1 }
        manager.reopenMainWindow { fallback += 1 }
        #expect(scene == 1 && fallback == 1)
    }

    @Test func `open in Space with the main window closed reopens it through the scene`() async throws {
        var scene = 0
        var fallback = 0
        manager.openMainWindow = { scene += 1 }
        let mini = manager.openNew(loading: TestPages.url("page"), source: .link)
        try await waitUntil { mini.tab.title == "page" && !mini.tab.isLoading }
        manager.openInSpace(mini) { manager.reopenMainWindow { fallback += 1 } }
        #expect(scene == 1 && fallback == 0)
        #expect(session.spaces[0].tabManager.tabs.contains { $0 === mini.tab })
    }

    // MARK: Leaving for a window of its own, closing (ON18)

    @Test func `a tab leaves for a window of its own, except the only one of such a window or in a private window`() {
        let main = window()
        let tab = main.tabManager.newTab()
        #expect(main.canOpenInNewWindow)
        let state = main.detachToNewWindow(tab)
        let detached = WindowModels(session: session, spaceID: state.spaceID, windowTabsID: state.windowTabsID).window
        detached.windowDidAppear()
        #expect(!detached.canOpenInNewWindow)
        detached.activate()
        detached.tabManager.newTab()
        #expect(detached.canOpenInNewWindow)
        #expect(!WindowModel(session: BrowserSession.makePrivate(), defaults: nil).canOpenInNewWindow)
    }

    @Test(arguments: [true, false])
    func `a window closes even when its buttons are hidden with the sidebar`(buttonsHidden: Bool) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        WindowChrome.setButtonsHidden(buttonsHidden, in: window)
        #expect(window.isVisible)
        WindowChrome.close(window)
        #expect(!window.isVisible)
    }
}
