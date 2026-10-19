import Foundation
@testable import Matcha
import Testing
import WebKit

/// Tabs and windows as extensions see them, and what extensions can do with them (task 6.3).
@MainActor
struct ExtensionAdapterTests {
    private let session: BrowserSession
    private let model: WindowModel
    /// Kept here: the windows only hold it weakly, and follow nothing without a listener (audit C5).
    private let sink = FakeExtensionSink()
    private let windows: ExtensionWindows
    private let windowID: UUID

    init() throws {
        windows = ExtensionWindows(sink: sink)
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        model = WindowModel(session: session, defaults: nil)
        windows.windowDidAppear(model, window: nil)
        windows.update()
        windowID = try #require(windows.adapter(for: model)?.windowID)
    }

    private var tabManager: TabManager {
        model.space.tabManager
    }

    /// Context of an unloaded extension: the adapters only use it to check the controller.
    private func context() async throws -> WKWebExtensionContext {
        let folder = try TestExtension.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        return try await WKWebExtensionContext(for: WKWebExtension(resourceBaseURL: folder))
    }

    private func adapter(_ tab: BrowserTab) throws -> ExtensionTab {
        windows.update()
        return try #require(windows.adapter(for: tab))
    }

    @Test func `adapters implement what WebKit asks`() {
        let tab = ExtensionTab(id: UUID(), windows: windows)
        let tabSelectors = [
            "windowForWebExtensionContext:", "indexInWindowForWebExtensionContext:", "parentTabForWebExtensionContext:",
            "webViewForWebExtensionContext:", "titleForWebExtensionContext:", "isPinnedForWebExtensionContext:",
            "isPlayingAudioForWebExtensionContext:", "zoomFactorForWebExtensionContext:", "urlForWebExtensionContext:",
            "isLoadingCompleteForWebExtensionContext:", "isSelectedForWebExtensionContext:",
            "loadURL:forWebExtensionContext:completionHandler:", "reloadFromOrigin:forWebExtensionContext:completionHandler:",
            "goBackForWebExtensionContext:completionHandler:", "goForwardForWebExtensionContext:completionHandler:",
            "activateForWebExtensionContext:completionHandler:", "closeForWebExtensionContext:completionHandler:",
            "setPinned:forWebExtensionContext:completionHandler:", "setZoomFactor:forWebExtensionContext:completionHandler:",
            "duplicateUsingConfiguration:forWebExtensionContext:completionHandler:",
        ]
        for selector in tabSelectors {
            #expect(tab.responds(to: NSSelectorFromString(selector)), "\(selector)")
        }
        let window = ExtensionWindow(id: UUID(), windows: windows, type: .normal, isPrivate: false)
        let windowSelectors = [
            "tabsForWebExtensionContext:", "activeTabForWebExtensionContext:", "windowTypeForWebExtensionContext:",
            "windowStateForWebExtensionContext:", "isPrivateForWebExtensionContext:", "screenFrameForWebExtensionContext:",
            "frameForWebExtensionContext:", "focusForWebExtensionContext:completionHandler:",
            "closeForWebExtensionContext:completionHandler:",
        ]
        for selector in windowSelectors {
            #expect(window.responds(to: NSSelectorFromString(selector)), "\(selector)")
        }
        let manager = TestExtension.manager()
        let delegateSelectors = [
            "webExtensionController:openWindowsForExtensionContext:", "webExtensionController:focusedWindowForExtensionContext:",
            "webExtensionController:openNewWindowUsingConfiguration:forExtensionContext:completionHandler:",
            "webExtensionController:openNewTabUsingConfiguration:forExtensionContext:completionHandler:",
            "webExtensionController:openOptionsPageForExtensionContext:completionHandler:",
            "webExtensionController:promptForPermissions:inTab:forExtensionContext:completionHandler:",
            "webExtensionController:promptForPermissionToAccessURLs:inTab:forExtensionContext:completionHandler:",
            "webExtensionController:promptForPermissionMatchPatterns:inTab:forExtensionContext:completionHandler:",
            "webExtensionController:didUpdateAction:forExtensionContext:",
            "webExtensionController:presentPopupForAction:forExtensionContext:completionHandler:",
            "webExtensionController:sendMessage:toApplicationWithIdentifier:forExtensionContext:replyHandler:",
            "webExtensionController:connectUsingMessagePort:forExtensionContext:completionHandler:",
        ]
        for selector in delegateSelectors {
            #expect(manager.controllerDelegate.responds(to: NSSelectorFromString(selector)), "\(selector)")
        }
    }

    @Test func `a window holds every Space, favorites once`() async throws {
        let home = model.space
        let favorite = tabManager.newTab()
        tabManager.setPlace(favorite, to: .favorite)
        let pinned = tabManager.newTab()
        tabManager.setPlace(pinned, to: .pinned)
        let today = tabManager.newTab()
        model.newSpace()
        let other = tabManager.newTab()
        let expected = [favorite.id, pinned.id, today.id, other.id]
        windows.update()
        #expect(windows.tabs(inWindow: windowID).map(\.tabID) == expected)
        model.select(home)
        model.selectSpace(at: 1)
        windows.update()
        #expect(windows.tabs(inWindow: windowID).map(\.tabID) == expected)
        #expect(windows.adapter(for: favorite)?.page === favorite)

        let context = try await context()
        #expect(try adapter(favorite).isPinned(for: context))
        #expect(try adapter(pinned).isPinned(for: context))
        #expect(try !adapter(today).isPinned(for: context))
        #expect(try adapter(other).indexInWindow(for: context) == 3)
        let window = try #require(windows.adapter(for: model))
        #expect((window.activeTab(for: context) as? ExtensionTab)?.tabID == other.id)
        #expect(window.windowType(for: context) == .normal)
        #expect(window.windowState(for: context) == .normal)
        #expect(!window.isPrivate(for: context))
        #expect(window.frame(for: context).isNull)
    }

    @Test func `a tab reports its page`() async throws {
        let opener = tabManager.newTab()
        let tab = tabManager.insertTab(configuration: opener.configuration, after: opener, select: true)
        try tab.load(#require(URL(string: "about:blank")))
        try await waitUntil { tab.url != nil && !tab.isLoading }
        let context = try await context()
        let adapter = try adapter(tab)
        #expect((adapter.window(for: context) as? ExtensionWindow)?.windowID == windowID)
        #expect((adapter.parentTab(for: context) as? ExtensionTab)?.tabID == opener.id)
        #expect(adapter.url(for: context) == URL(string: "about:blank"))
        #expect(adapter.isLoadingComplete(for: context))
        #expect(adapter.isSelected(for: context))
        #expect(try !self.adapter(opener).isSelected(for: context))
        #expect(adapter.zoomFactor(for: context) == 1)
        // Unloaded context: no controller, so no web view for it.
        #expect(adapter.webView(for: context) == nil)
    }

    // MARK: Actions

    private func result(_ action: (@escaping @Sendable ((any Error)?) -> Void) -> Void) async -> (any Error)? {
        await withCheckedContinuation { continuation in
            action { continuation.resume(returning: $0) }
        }
    }

    @Test func `activating a tab of another Space shows that Space`() async throws {
        let home = model.space
        let first = tabManager.newTab()
        _ = tabManager.newTab()
        model.newSpace()
        _ = tabManager.newTab()
        let context = try await context()
        let adapter = try adapter(first)
        #expect(await result { adapter.activate(for: context, completionHandler: $0) } == nil)
        #expect(model.space === home)
        #expect(home.tabManager.selectedTab === first)
    }

    @Test func `closing, pinning and zooming a tab`() async throws {
        let tab = tabManager.newTab()
        let other = tabManager.newTab()
        let context = try await context()
        let adapter = try adapter(tab)
        #expect(await result { adapter.setPinned(true, for: context, completionHandler: $0) } == nil)
        #expect(tabManager.place(of: tab) == .pinned)
        #expect(await result { adapter.setPinned(false, for: context, completionHandler: $0) } == nil)
        #expect(tabManager.place(of: tab) == .today)
        #expect(await result { adapter.setZoomFactor(1.25, for: context, completionHandler: $0) } == nil)
        #expect(tab.pageZoom == 1.25)
        #expect(await result { adapter.goBack(for: context, completionHandler: $0) } != nil)
        let closing = try self.adapter(other)
        #expect(await result { closing.close(for: context, completionHandler: $0) } == nil)
        #expect(tabManager.tab(withID: other.id) == nil)
    }

    @Test func `a webpage tab does not load an extension page`() async throws {
        let tab = tabManager.newTab()
        let context = try await context()
        let adapter = try adapter(tab)
        let url = try #require(URL(string: "webkit-extension://matcha-test/options.html"))
        #expect(await result { adapter.loadURL(url, for: context, completionHandler: $0) } != nil)
        #expect(tab.url == nil)
    }

    @Test func `browser windows stay open, mini windows close`() async throws {
        let miniWindows = MiniWindowManager.forTests(session: session)
        windows.miniWindows = miniWindows
        let mini = miniWindows.openNew(source: .menu)
        windows.update()
        let context = try await context()
        let browser = try #require(windows.adapter(for: model))
        #expect(await result { browser.close(for: context, completionHandler: $0) } != nil)
        let window = windows.windowAdapter(mini.id)
        #expect(window.windowType(for: context) == .popup)
        #expect((window.activeTab(for: context) as? ExtensionTab)?.tabID == mini.tab.id)
        #expect(await result { window.close(for: context, completionHandler: $0) } == nil)
        #expect(miniWindows.windows.isEmpty)
    }
}
