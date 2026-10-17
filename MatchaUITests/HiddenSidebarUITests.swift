import XCTest

/// Barre latérale masquée (⌘S) et son apparition au survol du bord gauche.
final class HiddenSidebarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCommandSHidesAndShowsTheSidebarAndWindowButtons() {
        let app = launchApp()
        let window = app.windows.firstMatch
        let newTabButton = app.buttons["newTabButton"]
        XCTAssertTrue(newTabButton.waitForExistence(timeout: 5))
        moveAwayFromLeftEdge(in: window)

        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(newTabButton.waitForNonExistence(timeout: 3))
        XCTAssertFalse(window.buttons[XCUIIdentifierCloseWindow].exists)

        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(newTabButton.waitForExistence(timeout: 3))
        XCTAssertTrue(window.buttons[XCUIIdentifierCloseWindow].exists)
    }

    @MainActor
    func testHoveringTheLeftEdgeRevealsTheHiddenSidebar() {
        let app = launchApp()
        let window = app.windows.firstMatch
        let newTabButton = app.buttons["newTabButton"]
        XCTAssertTrue(newTabButton.waitForExistence(timeout: 5))
        moveAwayFromLeftEdge(in: window)
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(newTabButton.waitForNonExistence(timeout: 3))

        window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 3, dy: 0)).hover()
        XCTAssertTrue(newTabButton.waitForExistence(timeout: 3))
        XCTAssertTrue(window.buttons[XCUIIdentifierCloseWindow].exists)

        moveAwayFromLeftEdge(in: window)
        XCTAssertTrue(newTabButton.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testCommandLOpensTheCommandBarWithoutRevealingTheSidebar() {
        let app = launchApp()
        let window = app.windows.firstMatch
        let field = addressField(in: app)
        XCTAssertTrue(waitForBrowserWindow(of: app))
        moveAwayFromLeftEdge(in: window)
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(addressPill(in: app).waitForNonExistence(timeout: 3))

        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        XCTAssertFalse(app.buttons["newTabButton"].exists)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }
}
