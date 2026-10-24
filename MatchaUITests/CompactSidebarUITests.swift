import XCTest

/// Hidden sidebar reduced to a column of tab icons (Settings > Appearance, “Show Tab Icons”).
final class CompactSidebarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func compactTabs(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "compactTab")
    }

    /// The pointer over the page, away from the column.
    @MainActor
    private func hoverPage(in app: XCUIApplication) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).hover()
    }

    @MainActor
    func testHidingTheSidebarLeavesTheTabIconsAndHoveringShowsIt() {
        let app = launchApp(settings: ["hiddenSidebarStyle": "icons"])
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))

        // ⌃⌘S: the rows give way to the icons; the window's buttons and the sidebar button stay.
        hoverPage(in: app)
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(waitForCount(compactTabs(in: app), 2))
        XCTAssertTrue(waitForCount(tabRows(in: app), 0))
        XCTAssertTrue(app.buttons["sidebarToggleButton"].exists)

        // A click on an icon shows that tab.
        let second = compactTabs(in: app).element(boundBy: 1)
        XCTAssertFalse(second.isSelected)
        second.click()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: second)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 3), .completed)

        // The pointer stays on the column: the sidebar shows over the page, and leaves with the pointer.
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        hoverPage(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 0))

        // ⌃⌘S brings the sidebar back for good.
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        XCTAssertTrue(waitForCount(compactTabs(in: app), 0))
    }
}
