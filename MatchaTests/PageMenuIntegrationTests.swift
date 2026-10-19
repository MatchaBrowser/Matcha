import AppKit
@testable import Matcha
import Testing
import WebKit

/// Captures the next context menu as soon as it opens, as displayed (after Matcha's rewrite), chooses a Matcha item in
/// it as the user would (`performActionForItem`), then closes it. Everything happens during menu tracking, while
/// WebKit is still showing it. Any other menu that opens afterwards is closed at once.
@MainActor
final class ContextMenuDriver: NSObject {
    private let choice: PageMenuItem?
    private var menu: NSMenu?
    private var observers: [any NSObjectProtocol] = []
    /// Identifiers of the menu items (nil: separator).
    private(set) var identifiers: [String?] = []
    /// Matcha's items, in their places (nil: WebKit item).
    private(set) var choices: [PageMenuItem?] = []
    /// The menu was captured, then closed.
    private(set) var didClose = false

    var didOpen: Bool {
        menu != nil
    }

    init(choosing choice: PageMenuItem?) {
        self.choice = choice
        super.init()
        observe(NSMenu.didBeginTrackingNotification) { $0.menuDidOpen($1) }
        observe(NSMenu.didEndTrackingNotification) { driver, menu in
            if menu === driver.menu, !driver.identifiers.isEmpty {
                driver.didClose = true
            }
        }
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func observe(_ name: Notification.Name, _ handle: @escaping @MainActor (ContextMenuDriver, NSMenu) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            // Notification delivered on the main queue (`queue: .main`): the menu never leaves it.
            nonisolated(unsafe) let menu = notification.object as? NSMenu
            MainActor.assumeIsolated {
                if let self, let menu {
                    handle(self, menu)
                }
            }
        })
    }

    private func menuDidOpen(_ menu: NSMenu) {
        guard self.menu == nil else {
            menu.cancelTracking()
            return
        }
        self.menu = menu
        // The notification comes before `willOpenMenu` (observed): the menu is captured on the next turn, during its
        // tracking, when the main run loop runs in this mode.
        perform(#selector(chooseAndClose), with: nil, afterDelay: 0, inModes: [.eventTracking, .default])
    }

    @objc private func chooseAndClose() {
        guard let menu else {
            return
        }
        identifiers = menu.items.map { $0.identifier?.rawValue }
        choices = menu.items.map { ($0.representedObject as? PageMenuChoice)?.item }
        if let choice, let index = menu.items.firstIndex(where: { ($0.representedObject as? PageMenuChoice)?.item == choice }) {
            menu.performActionForItem(at: index)
        }
        menu.cancelTracking()
    }
}

/// Page context menu (task 5.9) on a real WebKit menu, opened by a simulated right-click in a real web view:
/// identifiers captured, WebKit item triggered, window put away. WebKit only opens its menu for a web view in a shown
/// window: the window is placed off every screen; the menu appears for a moment.
@MainActor
@Suite(.serialized)
final class PageMenuIntegrationTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
        styleMask: [.titled],
        backing: .buffered,
        defer: false,
    )
    private static let link = "<a href='\(TestPages.url("cible").absoluteString)' style='display:block;height:600px'>lien</a>"

    init() {
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    }

    isolated deinit {
        window.orderOut(nil)
    }

    /// Selected tab showing `body` (no margin), alone in the window, once the page is visible and laid out at the
    /// window's size, with `element` in the middle.
    private func showPage(_ body: String, element: String) async throws -> BrowserTab {
        let page = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        let webView = page.loadedWebView
        webView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        window.contentView = webView
        window.orderFront(nil)
        page.load(TestPages.url("source", body: "<style>body{margin:0}</style>" + body))
        try await waitUntil { page.title == "source" && !page.isLoading }
        let script = "document.visibilityState == 'visible' && document.elementFromPoint(400, 300)?.tagName == '\(element)'"
        let deadline = ContinuousClock.now + .seconds(5)
        while try await webView.evaluateJavaScript(script) as? Bool != true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        return page
    }

    /// Right-click in the middle of the page; the menu is captured, `choice` is chosen in it, then it closes. Right
    /// after another menu, WebKit may not open its own (observed): the click is retried, three times at most.
    private func rightClick(choosing choice: PageMenuItem?) async throws -> ContextMenuDriver {
        let driver = ContextMenuDriver(choosing: choice)
        for _ in 1 ... 3 {
            try sendRightClick()
            if await (try? waitUntil(timeout: .seconds(2)) { driver.didOpen }) != nil {
                break
            }
        }
        try await waitUntil { driver.didClose }
        // Time for WebKit and AppKit to be done with this menu before the next one.
        try await Task.sleep(for: .milliseconds(300))
        return driver
    }

    private func sendRightClick() throws {
        for type in [NSEvent.EventType.rightMouseDown, .rightMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type,
                location: NSPoint(x: 400, y: 300),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .rightMouseDown ? 1 : 0,
            ))
            window.sendEvent(event)
        }
    }

    @Test func `the link menu of WebKit gets new tab and Peek in place of new window`() async throws {
        _ = try await showPage(Self.link, element: "A")
        let driver = try await rightClick(choosing: nil)

        #expect(driver.choices.compactMap(\.self) == [.openLinkInNewTab, .openLinkInPeek])
        let openLink = try #require(driver.identifiers.firstIndex(of: "WKMenuItemIdentifierOpenLink"))
        #expect(driver.choices[openLink + 1] == .openLinkInNewTab)
        #expect(!driver.identifiers.contains("WKMenuItemIdentifierOpenLinkInNewWindow"))
        #expect(driver.identifiers.contains("WKMenuItemIdentifierCopyLink"))
        #expect(driver.identifiers.contains("WKMenuItemIdentifierDownloadLinkedFile"))
    }

    @Test func `open link in new tab from the menu adds a background tab`() async throws {
        let page = try await showPage(Self.link, element: "A")
        _ = try await rightClick(choosing: .openLinkInNewTab)

        try await waitUntil { manager.tabs.count == 2 }
        let added = manager.tabs[1]
        #expect(manager.tabs[0] === page)
        #expect(manager.selectedTab === page)
        #expect(manager.peek == nil)
        try await waitUntil { added.title == "cible" && !added.isLoading }
        #expect((page.webView as? BrowserWebView)?.pageMenuIntent.intent == nil)
    }

    @Test func `open link in Peek from the menu opens Peek`() async throws {
        let page = try await showPage(Self.link, element: "A")
        _ = try await rightClick(choosing: .openLinkInPeek)

        try await waitUntil { manager.peek != nil }
        let peek = try #require(manager.peek)
        #expect(peek.sourceTabID == page.id)
        try await waitUntil { peek.tab.title == "cible" && !peek.tab.isLoading }
        #expect(manager.tabs.count == 1)
    }

    @Test func `open image in new tab from the menu adds a background tab`() async throws {
        let image = TestPages.url("image.svg")
        let page = try await showPage("<img src='\(image.absoluteString)' style='display:block;width:800px;height:600px'>", element: "IMG")
        let driver = try await rightClick(choosing: .openImageInNewTab)

        #expect(driver.choices.compactMap(\.self) == [.openImageInNewTab])
        try await waitUntil { manager.tabs.count == 2 }
        #expect(manager.selectedTab === page)
        try await waitUntil { manager.tabs[1].url == image }
    }

    @Test func `the menu of a page gets back, forward, save, print and source`() async throws {
        _ = try await showPage("<div style='height:600px'></div>", element: "DIV")
        let driver = try await rightClick(choosing: nil)
        let reload = try #require(driver.identifiers.firstIndex(of: "WKMenuItemIdentifierReload"))
        #expect(Array(driver.identifiers[..<reload]) == ["MatchaMenuItemIdentifierGoBack", "MatchaMenuItemIdentifierGoForward"])
        #expect(driver.identifiers.contains("MatchaMenuItemIdentifierSaveAs"))
        #expect(driver.identifiers.contains("MatchaMenuItemIdentifierPrint"))
        #expect(driver.identifiers.contains("MatchaMenuItemIdentifierViewSource"))
    }
}
