import XCTest

/// Helpers for the mini window tests. Queries always target a specific window: the browser window and the mini
/// window each have their own address pill.
extension XCTestCase {
    /// Launch value of a KeyboardShortcuts shortcut (“-KeyboardShortcuts_openMiniWindow <value>”).
    /// The outer quotes are essential: `UserDefaults` then reads a string (the shortcut's JSON); without them,
    /// the value is lost.
    static func shortcutArgument(keyCode: Int, carbonModifiers: Int) -> String {
        #""{\"carbonKeyCode\":\#(keyCode),\"carbonModifiers\":\#(carbonModifiers)}""#
    }

    /// Open mini windows (panel identifier; fallback: the windows that have the mini window's × button).
    @MainActor
    func miniWindows(in app: XCUIApplication) -> XCUIElementQuery {
        let byIdentifier = app.windows.matching(identifier: "miniWindow")
        return byIdentifier.count > 0 ? byIdentifier : app.windows.containing(.button, identifier: "miniWindowClose")
    }

    /// Main browser window (neither a mini window nor a private window).
    @MainActor
    func browserWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows.containing(.button, identifier: "newTabButton")
            .matching(NSPredicate(format: "title != %@", "Navigation privée"))
            .firstMatch
    }

    /// “Open in ‹Space›” button of `mini`; its value is the name of the target Space.
    @MainActor
    func openInSpaceButton(in mini: XCUIElement) -> XCUIElement {
        mini.descendants(matching: .any).matching(identifier: "miniWindowOpenInSpace").firstMatch
    }

    /// File > New Mini Window: the mini window opens, bar open, its field has keyboard focus.
    @MainActor
    @discardableResult
    func openMiniWindow(in app: XCUIApplication) -> XCUIElement {
        let count = miniWindows(in: app).count
        app.menuBars.menuBarItems["Fichier"].click()
        app.menuBars.menuItems["Nouvelle mini-fenêtre"].click()
        XCTAssertTrue(waitForCount(miniWindows(in: app), count + 1, timeout: 5))
        // The new one is the only one whose bar is open: the others lost keyboard focus, their bar closed.
        // It is then identified by its index, not by this field, which disappears as soon as an address is submitted.
        let windows = miniWindows(in: app)
        XCTAssertTrue(windows.containing(.textField, identifier: "addressField").firstMatch.waitForExistence(timeout: 3))
        let index = windows.allElementsBoundByIndex.firstIndex { $0.textFields["addressField"].exists } ?? 0
        let mini = windows.element(boundBy: index)
        let field = addressField(in: mini)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        return mini
    }

    /// Types `text` then Return in the bar of `mini` (already open), and waits for the pill to show it.
    @MainActor
    func load(_ text: String, in mini: XCUIElement, app: XCUIApplication) {
        let field = addressField(in: mini)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        app.typeText("\(text)\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: addressPill(in: mini)) { $0 == text })
    }

    /// Point of the browser window that the mini window doesn't cover (at the edge of the sidebar or of the page, on
    /// the background).
    @MainActor
    func uncoveredPoint(of browser: XCUIElement, avoiding mini: XCUIElement) -> XCUICoordinate {
        let offsets = [CGVector(dx: 0.05, dy: 0.5), CGVector(dx: 0.95, dy: 0.5), CGVector(dx: 0.5, dy: 0.05), CGVector(dx: 0.5, dy: 0.95)]
        let frame = browser.frame
        let miniFrame = mini.frame
        let chosen = offsets.first { offset in
            !miniFrame.contains(CGPoint(x: frame.minX + frame.width * offset.dx, y: frame.minY + frame.height * offset.dy))
        } ?? offsets[0]
        return browser.coordinate(withNormalizedOffset: chosen)
    }
}
