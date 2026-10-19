import XCTest

/// Private browsing window (⇧⌘N).
final class PrivateWindowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPrivateWindowHasItsOwnTabsAndForgetsThem() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        let badge = app.descendants(matching: .any).matching(identifier: "privateBadge").firstMatch
        XCTAssertFalse(badge.exists)

        let privateWindow = openPrivateWindow(in: app)
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 2)
        // The private window opens without the command bar, on the empty page; ⌘T opens the bar in this
        // window, without a prior click.
        let hint = privateWindow.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Appuyez sur ⌘T")).firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 3))
        openEmptyTab(in: app, window: privateWindow)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        openEmptyTab(in: app, window: privateWindow)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        // ⌘W closes a tab, not the window.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(badge.exists)

        // Closing the private window forgets its tabs; the next one starts from scratch.
        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(badge.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForCount(tabRows(in: app), 0))
        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertEqual(tabRows(in: app).count, 0)
    }
}
