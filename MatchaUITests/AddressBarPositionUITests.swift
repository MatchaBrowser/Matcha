import XCTest

/// Address bar in the sidebar or above the page, navigation buttons.
final class AddressBarPositionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddressBarAboveThePage() {
        let app = launchApp(settings: ["addressBarPosition": "top"])
        let window = app.windows.firstMatch
        let pill = addressPill(in: app)
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        // To the right of the sidebar, which keeps its tabs.
        XCTAssertGreaterThan(pill.frame.minX - window.frame.minX, 180)
        XCTAssertTrue(app.buttons["newTabButton"].exists)
        XCTAssertTrue(app.buttons["Précédent"].exists)

        // The pill opens the command bar.
        pill.click()
        let field = addressField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        app.typeText("about:blank\n")
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(waitForValue(of: pill) { $0 == "about:blank" })
    }

    @MainActor
    func testHiddenSidebarKeepsTheAddressBarAboveThePage() {
        let app = launchApp(settings: ["addressBarPosition": "top"])
        let window = app.windows.firstMatch
        let field = addressField(in: app)
        XCTAssertTrue(waitForBrowserWindow(of: app))
        moveAwayFromLeftEdge(in: window)
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(app.buttons["newTabButton"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(addressPill(in: app).exists)

        // ⌘L opens the command bar without revealing the sidebar.
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        XCTAssertFalse(app.buttons["newTabButton"].exists)
    }

    @MainActor
    func testNavigationButtonsCanBeHidden() {
        for position in ["sidebar", "top"] {
            let app = launchApp(settings: ["addressBarPosition": position, "showsNavigationButtons": "NO"])
            XCTAssertTrue(waitForBrowserWindow(of: app))
            XCTAssertFalse(app.buttons["Précédent"].exists, "position \(position)")
            XCTAssertFalse(app.buttons["Recharger"].exists, "position \(position)")
            app.terminate()
        }
    }
}
