import XCTest

/// Command bar (⌘T, ⌘L): opening, closing, rows and keyboard. Offline: tabs are told apart by
/// `about:blank?…` (WebKit rewrites `#` as `%23`).
final class CommandBarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func spaceButtons(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "spaceButton")
    }

    /// Row of the bar whose title is exactly `title`.
    @MainActor
    private func commandBarRow(titled title: String, in scope: XCUIElement) -> XCUIElement {
        commandBarRows(in: scope).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// Launches the app (no tab, bar closed) and waits for its window.
    @MainActor
    private func launch() -> XCUIApplication {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        return app
    }

    /// Launches the app, opens the bar (⌘T) and waits until its field has keyboard focus.
    @MainActor
    private func launchAndOpenBar() -> (app: XCUIApplication, field: XCUIElement) {
        let app = launch()
        return (app, openCommandBar(in: app))
    }

    @MainActor
    func testEscapeLeavesNoTab() {
        let (app, field) = launchAndOpenBar()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 0)
    }

    @MainActor
    func testReturnWithoutTextOpensAnEmptyTab() {
        let app = launch()
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertFalse(addressField(in: app).exists)
    }

    @MainActor
    func testTypedAddressOpensInANewTab() {
        let (app, _) = launchAndOpenBar()
        app.typeText("about:blank?one")
        let first = commandBarRows(in: app).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(first.label.contains("about:blank?one"), first.label)

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "about:blank?one" })
    }

    @MainActor
    func testCommandLEditsTheShownTab() {
        let app = launch()
        openAddress("about:blank?one", in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))

        // The full URL, selected: address row then “Copy URL”.
        let field = openCommandBar(in: app, newTab: false)
        XCTAssertTrue(waitForValue(of: field) { $0 == "about:blank?one" })
        let rows = commandBarRows(in: app)
        XCTAssertTrue(waitForCount(rows, 2))
        XCTAssertEqual(rows.element(boundBy: 1).label, "Copier l'URL")

        // Typing replaces the address; it opens in the same tab.
        app.typeText("about:blank?two\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "about:blank?two" })
        XCTAssertEqual(tabRows(in: app).count, 1)
    }

    @MainActor
    func testArrowsAndReturnSwitchToAnOpenTab() {
        let app = launch()
        openAddress("about:blank?one", in: app)
        openAddress("about:blank?two", in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))

        // “blank”: the search, then the ?one tab (the displayed tab is not suggested).
        let field = openCommandBar(in: app)
        app.typeText("blank")
        let rows = commandBarRows(in: app)
        XCTAssertTrue(waitForCount(rows, 2))

        // The selection doesn't wrap around.
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(rows.element(boundBy: 0).isSelected)
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(rows.element(boundBy: 1).isSelected)
        XCTAssertFalse(rows.element(boundBy: 0).isSelected)

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "about:blank?one" })
        XCTAssertEqual(tabRows(in: app).count, 2)
    }

    @MainActor
    func testCommandWClosesOnlyTheBar() {
        let app = launch()
        openAddress("about:blank?one", in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))

        let field = openCommandBar(in: app)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 1)
    }

    @MainActor
    func testClickingOutsideClosesTheBarAndReachesTheTarget() {
        let app = launch()
        openAddress("about:blank?one", in: app)
        openAddress("about:blank?two", in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))

        let field = openCommandBar(in: app)
        // The click closes the bar and selects the tab, on the first try.
        tabRow(titled: "about:blank?one", in: app).click()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "about:blank?one" })
    }

    @MainActor
    func testSwitchingSpaceClosesTheBar() {
        let app = launch()
        createSpace(in: app)
        XCTAssertTrue(waitForCount(spaceButtons(in: app), 2))
        let field = openCommandBar(in: app)
        app.typeText("swift")
        // ⌃1: the Spaces menu switches to the first Space; the bar closes without opening anything.
        app.typeKey("1", modifierFlags: .control)
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 0)
    }

    @MainActor
    func testNewSpaceAction() {
        let (app, _) = launchAndOpenBar()
        app.typeText("space")
        let row = commandBarRow(titled: "Nouveau Space", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        XCTAssertTrue(waitForCount(spaceButtons(in: app), 2))
    }

    @MainActor
    func testSettingsAction() {
        let (app, _) = launchAndOpenBar()
        app.typeText("réglages")
        let row = commandBarRow(titled: "Réglages", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        XCTAssertTrue(waitForCount(app.windows, 2, timeout: 5))

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(app.windows, 1))
    }

    @MainActor
    func testPrivateWindowHasNoNewSpaceAction() {
        let app = launch()
        let privateWindow = openPrivateWindow(in: app)
        openCommandBar(in: app, window: privateWindow)

        app.typeText("space")
        XCTAssertFalse(commandBarRow(titled: "Nouveau Space", in: privateWindow).waitForExistence(timeout: 1))
        // Only the text search remains.
        XCTAssertEqual(commandBarRows(in: privateWindow).count, 1)
    }
}
