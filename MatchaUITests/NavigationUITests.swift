import XCTest

/// Navigation and shortcuts: we drive the app like a user.
final class NavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStartsWithoutTabsOrCommandBar() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        XCTAssertEqual(tabRows(in: app).count, 0)
        // The bar never opens by itself: the empty page suggests ⌘T.
        let hint = "Appuyez sur ⌘T"
        let predicate = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", hint, hint)
        XCTAssertTrue(app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(addressField(in: app).waitForExistence(timeout: 1))
    }

    @MainActor
    func testAddressFieldLoadsPage() throws {
        try skipIfOffline()
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openAddress("example.com", in: app)

        XCTAssertTrue(tabRow(titled: "Example Domain", in: app).waitForExistence(timeout: 20))
        XCTAssertEqual(tabRows(in: app).count, 1)
        // The pill only shows the domain.
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "example.com" })
    }

    // MARK: Shortcuts

    @MainActor
    func testCommandTOpensTheCommandBarWithoutCreatingATab() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))

        // ⌘T opens the bar without creating a tab; Escape leaves nothing behind.
        let field = openCommandBar(in: app)
        XCTAssertEqual(tabRows(in: app).count, 0)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 0)

        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
    }

    @MainActor
    func testCommandWClosesTabsButNotTheWindow() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))

        app.typeKey("w", modifierFlags: .command)
        XCTAssertEqual(tabRows(in: app).count, 1)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertEqual(tabRows(in: app).count, 0)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertEqual(app.windows.count, 1)
    }

    @MainActor
    func testCommandShiftWClosesTheWindow() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.windows.firstMatch.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testCommandLFocusesAddressField() {
        let app = launchApp()
        let field = addressField(in: app)
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        tabRows(in: app).firstMatch.click()
        XCTAssertFalse(field.exists)

        // Empty tab: the bar opens with an empty text.
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        XCTAssertEqual(field.value as? String, "")
    }

    @MainActor
    func testHistoryShortcutsGoBackAndForward() throws {
        try skipIfOffline()
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openAddress("example.com", in: app)
        XCTAssertTrue(tabRow(titled: "Example Domain", in: app).waitForExistence(timeout: 20))

        openAddress("example.org", in: app, newTab: false)
        let pill = addressPill(in: app)
        XCTAssertTrue(waitForValue(of: pill) { $0 == "example.org" })

        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(waitForValue(of: pill) { $0 == "example.com" })
        app.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(waitForValue(of: pill) { $0 == "example.org" })
        XCTAssertEqual(tabRows(in: app).count, 1)
    }

    @MainActor
    func testCommandWKeepsPinnedTabs() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Épingler"].click()
        tabRows(in: app).firstMatch.click()

        // The pinned tab stays; the selection moves to the Today tab, which ⌘W closes for good.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
    }
}
