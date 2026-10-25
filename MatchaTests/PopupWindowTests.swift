import AppKit
import Foundation
@testable import Matcha
import Testing
import WebKit

/// Sign-in windows (task 5.8) opened from the tabs of a Space and their Peek, by the navigation delegate, with real web
/// views, the pages of `TestPages` and real windows (never shown). A class: windows left open are closed at the end of
/// each test (their SwiftUI view retains their controller until they close: their pages would keep running until the
/// end of the tests). One test at a time: fewer web views at once, so the waits of the other suites (10 s) are not
/// exceeded.
@MainActor
@Suite(.webKit, .serialized)
final class PopupWindowTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let popups = PopupWindowManager.forTests()
    private let pages = CountingTestPages()

    init() {
        manager.popupWindows = popups
    }

    isolated deinit {
        popups.closeAll()
    }

    /// Selected tab on a local page, at the top, followed by another empty tab.
    private func openPage() async throws -> (page: BrowserTab, other: BrowserTab) {
        let other = manager.newTab()
        let page = manager.insertTab(configuration: pages.configuration(), after: nil, select: true)
        page.load(TestPages.url("ouvrant"))
        try await waitUntil { page.title == "ouvrant" && !page.isLoading }
        return (page, other)
    }

    /// Sign-in window of the local page `name`, opened by `webView` with a size, once loaded.
    private func openPopup(_ name: String = "connexion", from webView: WKWebView, count: Int = 1) async throws -> PopupWindowController {
        try await webView.openWindow(TestPages.url(name), features: "width=500,height=600")
        try await waitUntil { popups.windows.count == count }
        let popup = popups.windows[count - 1]
        try await waitUntil { popup.tab.title == name && !popup.tab.isLoading }
        return popup
    }

    @Test func `window open with a size opens a sign-in window instead of a tab`() async throws {
        let (page, other) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)

        #expect(manager.tabs.map(\.id) == [page.id, other.id])
        #expect(manager.selectedTab === page)
        #expect(popup.opener.page === page)
        #expect(popup.tab.openerID == page.id)
        #expect(popup.container.webView === popup.tab.webView)
        #expect(popup.tab.loadedWebView.uiDelegate === popups.coordinator)
        // Created with the configuration provided by WebKit: the originating page remains reachable.
        #expect(try await popup.tab.loadedWebView.hasOpener())
        // The page at the requested size, below the address bar; without an originating window, centered on screen.
        let content = popup.window.contentRect(forFrameRect: popup.window.frame)
        #expect(content.size == CGSize(width: 500, height: 600 + PopupAddressBar.height))
        #expect(abs(popup.window.frame.midX - PopupWindowManager.testScreen.midX) <= 0.5)
        #expect(abs(popup.window.frame.midY - PopupWindowManager.testScreen.midY) <= 0.5)
    }

    /// Bars hidden without a size: a tab too (only the size matters, as in Safari).
    @Test func `window open without a size still opens a tab`() async throws {
        let (page, _) = try await openPage()
        try await page.loadedWebView.openWindow(TestPages.url("onglet"), features: "toolbar=no,menubar=no")
        try await waitUntil { manager.tabs.count == 3 }
        #expect(popups.windows.isEmpty)
        #expect(manager.selectedTab === manager.tabs[1])
    }

    @Test func `window close from the page closes its sign-in window`() async throws {
        let (page, _) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)

        _ = try await popup.tab.loadedWebView.evaluateJavaScript("window.close(); true")

        try await waitUntil { popups.windows.isEmpty }
        #expect(!popup.tab.isLoaded)
        #expect(page.isLoaded)
        #expect(manager.tabs.count == 2)
    }

    @Test func `command W closes the sign-in window, not a tab`() async throws {
        let (page, _) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)
        let event = try #require(Self.keyEvent("w", modifiers: .command))

        #expect(popup.window.performKeyEquivalent(with: event))

        #expect(popups.windows.isEmpty)
        #expect(!popup.tab.isLoaded)
        #expect(manager.tabs.count == 2)
    }

    @Test func `only command W alone is the close shortcut`() throws {
        #expect(try PopupWindow.isCloseShortcut(#require(Self.keyEvent("w", modifiers: .command))))
        #expect(try PopupWindow.isCloseShortcut(#require(Self.keyEvent("w", modifiers: [.command, .capsLock]))))
        #expect(try !PopupWindow.isCloseShortcut(#require(Self.keyEvent("w", modifiers: [.command, .shift]))))
        #expect(try !PopupWindow.isCloseShortcut(#require(Self.keyEvent("w", modifiers: []))))
        #expect(try !PopupWindow.isCloseShortcut(#require(Self.keyEvent("q", modifiers: .command))))
    }

    @Test func `from Peek the sign-in window opens and Peek stays a peek`() async throws {
        let (page, other) = try await openPage()
        let peek = try #require(manager.openPeek(TestPages.url("apercu"), from: page))
        try await waitUntil { peek.tab.title == "apercu" && !peek.tab.isLoading }

        let popup = try await openPopup(from: peek.tab.loadedWebView)

        #expect(manager.peek?.tab === peek.tab)
        #expect(manager.tabs.map(\.id) == [page.id, other.id])
        #expect(popup.opener.page === peek.tab)
        #expect(try await popup.tab.loadedWebView.hasOpener())
    }

    /// ⌘-click and window without a size in the sign-in window: as from the originating page.
    @Test func `links of a sign-in window open in the opener's window`() async throws {
        let (page, other) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)
        let recorder = PolicyRecorder()
        let action = FakeNavigationAction(url: TestPages.url("conditions"), modifierFlags: .command)

        popups.coordinator.webView(popup.tab.loadedWebView, decidePolicyFor: action, decisionHandler: recorder.record)

        #expect(recorder.policies == [.cancel])
        #expect(manager.tabs.count == 3)
        #expect(manager.tabs[0] === page && manager.tabs[2] === other)
        #expect(manager.selectedTab === page)
        try await waitUntil { manager.tabs[1].title == "conditions" }

        _ = try await popup.tab.loadedWebView.evaluateJavaScript("window.open('\(TestPages.url("aide").absoluteString)'); true")
        try await waitUntil { manager.tabs.count == 4 }
        #expect(manager.selectedTab?.openerID == page.id)
        #expect(popups.windows.count == 1)
    }

    /// Originating page closed: a window without a size opened by the sign-in window becomes another one.
    @Test func `without its opener a sign-in window opens another one`() async throws {
        let (page, _) = try await openPage()
        let first = try await openPopup(from: page.loadedWebView)
        manager.close(page)

        _ = try await first.tab.loadedWebView.evaluateJavaScript("window.open('\(TestPages.url("suite").absoluteString)'); true")

        try await waitUntil { popups.windows.count == 2 }
        let second = popups.windows[1]
        #expect(second.opener.page === first.tab)
        try await waitUntil { second.tab.title == "suite" }
        #expect(manager.tabs.count == 1)
    }

    @Test func `a sign-in window can open another one with a size`() async throws {
        let (page, _) = try await openPage()
        let first = try await openPopup(from: page.loadedWebView)
        let second = try await openPopup("securite", from: first.tab.loadedWebView, count: 2)
        #expect(second.opener.page === first.tab)
        #expect(second.opener.host === popups)
        #expect(manager.tabs.count == 2)
    }

    @Test func `shift click stays a plain click in a sign-in window`() async throws {
        let (page, _) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)
        let recorder = PolicyRecorder()
        let action = FakeNavigationAction(url: TestPages.url("suite"), modifierFlags: .shift)
        popups.coordinator.webView(popup.tab.loadedWebView, decidePolicyFor: action, decisionHandler: recorder.record)
        #expect(recorder.policies == [.allow])
        #expect(manager.peek == nil)
    }

    /// Task 5.7: the page of a sign-in window is visible, so it reloads at once.
    @Test func `a crashed sign-in page reloads at once`() async throws {
        let (page, _) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)
        popups.coordinator.webViewWebContentProcessDidTerminate(popup.tab.loadedWebView)
        try await waitUntil { pages.count("connexion") == 2 && !popup.tab.crash.isRecovering && !popup.tab.isLoading }
        #expect(popups.windows.count == 1)
    }

    /// Task 5.1: a window that only downloads closes; the download completes. A `blob:` file: observed, neither a
    /// response from a test scheme handler nor a `data:` address opened in a new window becomes a download.
    @Test func `a sign-in window that only downloads closes`() async throws {
        let folder = try TemporaryDownloadsFolder()
        let downloads = folder.makeManager()
        popups.coordinator.downloadManager = downloads
        let (page, _) = try await openPage()

        _ = try await page.loadedWebView.evaluateJavaScript("""
        const url = URL.createObjectURL(new Blob(['relevé'], {type: 'application/octet-stream'}));
        window.open(url, '_blank', 'width=400,height=400'); true
        """)

        try await waitUntil { downloads.items.count == 1 && !downloads.items[0].isActive }
        #expect(downloads.items[0].state == .finished)
        #expect(folder.contents().count == 1)
        try await waitUntil { popups.windows.isEmpty }
        #expect(manager.tabs.count == 2)
    }

    /// A window that shows a page stays open when it downloads.
    @Test func `a sign-in window that shows a page stays open when it downloads`() async throws {
        let (page, _) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)
        popups.downloadDidStart(in: popup.tab.loadedWebView)
        #expect(popups.windows.count == 1)
    }

    /// The sign-in window stays above its originating window; once that one is closed, it stays open, alone.
    @Test func `the sign-in window follows its opener window until it closes`() async throws {
        let (page, _) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)
        let parent = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true,
        )
        parent.isReleasedWhenClosed = false
        parent.level = .floating

        popup.attach(to: parent)
        #expect(popup.window.parent === parent)
        #expect(popup.window.level == .floating)

        parent.close()
        #expect(popup.window.parent == nil)
        #expect(popup.window.level == .normal)
        #expect(popups.windows.count == 1)
        popup.close()
        #expect(popups.windows.isEmpty)
    }

    private static func keyEvent(_ characters: String, modifiers: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 13,
        )
    }
}
