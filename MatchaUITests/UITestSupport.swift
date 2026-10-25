import AppKit
import XCTest

/// Shared helpers for the UI tests. Everything is synchronous: calls to XCUIApplication from
/// asynchronous code can block.
extension XCTestCase {
    /// Waits for the value of `element` to satisfy `condition`.
    @MainActor
    func waitForValue(of element: XCUIElement, timeout: TimeInterval = 20, _ condition: @escaping (String) -> Bool) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let value = (object as? XCUIElement)?.value as? String else {
                return false
            }
            return condition(value)
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    /// Waits for `query` to count `expected` elements: animated changes aren't instantaneous.
    @MainActor
    func waitForCount(_ query: XCUIElementQuery, _ expected: Int, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "count == %d", expected)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: query)], timeout: timeout) == .completed
    }

    /// Clicks `element` once its position is stable: right after a drag and drop or an animated opening,
    /// the view is still moving and an immediate click would target the element's old spot.
    @MainActor
    func clickWhenSettled(_ element: XCUIElement, timeout: TimeInterval = 3) {
        var previous = element.frame
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            let current = element.frame
            if current == previous {
                break
            }
            previous = current
        }
        // At the center, by coordinates: a page link is entirely covered by its text, and XCTest then refuses
        // to click the element itself.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    /// Puts the pointer in the middle of the page, far from the edge that reveals the hidden sidebar.
    @MainActor
    func moveAwayFromLeftEdge(in window: XCUIElement) {
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).hover()
    }

    @MainActor
    func waitForKeyboardFocus(of element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate { object, _ in
            ((object as? XCUIElement)?.value(forKey: "hasKeyboardFocus") as? Bool) == true
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    /// Drags `element` horizontally from its center.
    @MainActor
    func drag(_ element: XCUIElement, by distance: CGFloat) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: distance, dy: 0)))
    }

    /// Settings forced at each launch: the app's default values (the user's real settings must not
    /// change the test results), without the alert before quitting (it would block relaunches). The
    /// sidebar width isn't forced: the resize test must be able to change it.
    static let defaultSettings = [
        "ApplePersistenceIgnoreState": "YES",
        // In-memory store: the tests neither read nor change the user's tabs.
        "inMemoryStore": "YES",
        "confirmBeforeQuitting": "NO",
        "searchEngine": "google",
        "appearance": "system",
        "homePage": "",
        "newTabPage": "blank",
        "showsHomeButton": "NO",
        "addressBarPosition": "sidebar",
        "showsNavigationButtons": "YES",
        // Never any request to the search engine during the tests.
        "showsSearchSuggestions": "NO",
        // Links of Favorites and pinned tabs stay in their tab (the app's default value).
        "opensPinnedLinksInPeek": "NO",
        // No global shortcut for the mini window (text “NO”: no shortcut, nothing is written): ⌥⌘N
        // stays with the user's Matcha. The shortcut test sets another one.
        "KeyboardShortcuts_openMiniWindow": "NO",
        // No sleeping of hidden tabs (“Never”): a slow test doesn't see its pages reload. The sleep test gives a
        // short delay (`tabSuspensionDelaySeconds`, Debug only).
        "tabSuspensionDelay": "0",
    ]

    /// Language forced at each launch: the tests look up elements by their French texts,
    /// whatever the Mac's language.
    static let languageArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]

    /// Browser window forced at each launch: 1400 × 900 pt at the top left of the main screen.
    /// The position remembered by the app (“NSWindow Frame browser”, maybe on another screen, turned off or
    /// busy) no longer affects the tests; the user's one isn't changed.
    @MainActor
    static var windowFrameArguments: [String] {
        guard let screen = NSScreen.screens.first?.visibleFrame else {
            return []
        }
        let width = min(1400, screen.width - 80)
        let height = min(900, screen.height - 80)
        let frame = [screen.minX + 40, screen.maxY - 40 - height, width, height]
        let values = (frame + [screen.minX, screen.minY, screen.width, screen.height]).map { String(Int($0)) }
        return ["-NSWindow Frame browser", values.joined(separator: " ")]
    }

    /// Launches the app in French, without restoring the windows of a previous launch, with the default
    /// settings plus `settings`, for this launch only (“-key value”), without touching the user's
    /// ones. The window opens on the main screen.
    @MainActor
    func launchApp(settings: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += Self.languageArguments + Self.windowFrameArguments
        var values = Self.defaultSettings
        values.merge(settings) { _, new in new }
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            app.launchArguments += ["-\(key)", value]
        }
        app.launch()
        return app
    }

    /// New Space, from the menu of the account's circle at the bottom of the sidebar.
    @MainActor
    func createSpace(in app: XCUIApplication) {
        app.descendants(matching: .any).matching(identifier: "accountButton").firstMatch.click()
        clickOpenMenuItem("Nouveau Space", in: app)
    }

    /// Clicks the item `title` of the open menu (pop-up or context menu). The same title can also be in a closed menu
    /// of the menu bar (Spaces): the open menu's item is the one that can be clicked.
    @MainActor
    func clickOpenMenuItem(_ title: String, in app: XCUIApplication) {
        let items = app.menuItems.matching(NSPredicate(format: "title == %@", title))
        XCTAssertTrue(items.firstMatch.waitForExistence(timeout: 3))
        let item = items.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(item, "No open menu item “\(title)”")
        item?.click()
    }

    /// Browser window ready: its “New Tab” button is shown. The command bar never
    /// opens by itself, at launch or in a new window.
    @MainActor
    func waitForBrowserWindow(of app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        app.buttons["newTabButton"].waitForExistence(timeout: timeout)
    }

    /// New private window (⇧⌘N), without the command bar. No click afterwards: the next shortcut
    /// (⌘T) must reach it right away, as for the user.
    @MainActor
    func openPrivateWindow(in app: XCUIApplication) -> XCUIElement {
        app.typeKey("n", modifierFlags: [.command, .shift])
        let window = app.windows.matching(NSPredicate(format: "title == %@", "Navigation privée")).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        // The bar never opens by itself (checked before any click, which would close it).
        XCTAssertFalse(addressField(in: window).waitForExistence(timeout: 1))
        return window
    }

    /// Field of the command bar; `scope`: the app, or a specific window (private window).
    @MainActor
    func addressField(in scope: XCUIElement) -> XCUIElement {
        scope.textFields["addressField"]
    }

    /// Address pill (button): its value is the displayed domain.
    @MainActor
    func addressPill(in scope: XCUIElement) -> XCUIElement {
        scope.descendants(matching: .any).matching(identifier: "addressPill").firstMatch
    }

    @MainActor
    func commandBarRows(in scope: XCUIElement) -> XCUIElementQuery {
        scope.descendants(matching: .any).matching(identifier: "commandBarRow")
    }

    /// ⌘T (new tab) or ⌘L (displayed tab): the command bar opens and its field takes keyboard
    /// focus. `window`: the window where it must open (private window).
    @MainActor
    @discardableResult
    func openCommandBar(in app: XCUIApplication, window: XCUIElement? = nil, newTab: Bool = true) -> XCUIElement {
        app.typeKey(newTab ? "t" : "l", modifierFlags: .command)
        let field = addressField(in: window ?? app)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        return field
    }

    /// ⌘T then Return without text: an empty tab, like the old ⌘T. `window`: the target window
    /// (private window).
    @MainActor
    func openEmptyTab(in app: XCUIApplication, window: XCUIElement? = nil) {
        let field = openCommandBar(in: app, window: window)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }

    /// ⌘T (new tab) or ⌘L (displayed tab), then `text` and Return.
    @MainActor
    func openAddress(_ text: String, in app: XCUIApplication, newTab: Bool = true) {
        let field = openCommandBar(in: app, newTab: newTab)
        app.typeText("\(text)\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func tabRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "tabRow")
    }

    /// Tab row whose title contains `title`.
    @MainActor
    func tabRow(titled title: String, in app: XCUIApplication) -> XCUIElement {
        tabRows(in: app).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    // MARK: Split view

    /// Cards of the displayed panes (a single one outside a split, even without a tab).
    @MainActor
    func pagePanes(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "pagePane")
    }

    /// Cards of the panes from left to right.
    @MainActor
    func orderedPagePanes(in app: XCUIApplication) -> [XCUIElement] {
        pagePanes(in: app).allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
    }

    @MainActor
    func splitRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "splitRow")
    }

    @MainActor
    func splitSegments(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "splitSegment")
    }

    /// Piece of a split's row whose title contains `title`.
    @MainActor
    func splitSegment(titled title: String, in app: XCUIApplication) -> XCUIElement {
        splitSegments(in: app).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// Handle between the first two panes.
    @MainActor
    func splitDivider(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "splitDivider").firstMatch
    }

    /// “Open in Split View” in the menu of the tab row `title`.
    @MainActor
    func openInSplit(_ title: String, in app: XCUIApplication) {
        tabRow(titled: title, in: app).rightClick()
        app.menuItems["Ouvrir en split"].click()
    }

    /// Drags the tab row `title` to `target`, slowly, with a pause on arrival: the card's drop zone has
    /// time to pick its edge.
    @MainActor
    func dragTab(titled title: String, to target: XCUICoordinate, in app: XCUIApplication) {
        tabRow(titled: title, in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    /// Tests that load a real page are skipped without Internet access.
    func skipIfOffline() throws {
        let reachable = expectation(description: "example.com answers")
        var request = URLRequest(url: URL(string: "https://example.com/")!)
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if data != nil {
                reachable.fulfill()
            }
        }.resume()
        let online = XCTWaiter().wait(for: [reachable], timeout: 6) == .completed
        try XCTSkipUnless(online, "No access to example.com")
    }
}
