import XCTest

/// Several browsing windows: ⌘N (the same sidebar, a tab shown by one window at a time) and a tab opened in a window of
/// its own (“Open in New Window”, Arc's “This Window”).
final class MultiWindowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Browsing window `index` of the group, in opening order (1: the one of the launch).
    @MainActor
    private func browserWindow(_ index: Int, in app: XCUIApplication) -> XCUIElement {
        app.windows["browser-AppWindow-\(index)"]
    }

    @MainActor
    private func rows(in window: XCUIElement) -> XCUIElementQuery {
        window.descendants(matching: .any).matching(identifier: "tabRow")
    }

    /// “Open in Another Window”, in place of a page shown by another window.
    @MainActor
    private func shownElsewhere(in window: XCUIElement) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: "shownElsewhere").firstMatch
    }

    @MainActor
    func testCommandNOpensAWindowOnTheSameSpaceWithoutATab() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        app.typeKey("n", modifierFlags: .command)
        let second = browserWindow(2, in: app)
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        // Same sidebar, no tab selected: the empty page.
        XCTAssertTrue(waitForCount(rows(in: second), 1))
        XCTAssertFalse(rows(in: second).firstMatch.isSelected)
        XCTAssertFalse(shownElsewhere(in: second).exists)
    }

    @MainActor
    func testATabChosenInTwoWindowsCanBeShownHere() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        let first = browserWindow(1, in: app)
        app.typeKey("n", modifierFlags: .command)
        let second = browserWindow(2, in: app)
        XCTAssertTrue(second.waitForExistence(timeout: 5))

        // The first window's tab, chosen in the second one: the second shows it, the first offers to take it back.
        rows(in: second).firstMatch.click()
        XCTAssertTrue(shownElsewhere(in: first).waitForExistence(timeout: 3))
        // The second window, cascaded, covers the first but its top strip: a click there brings it to the front.
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 6)).click()
        first.buttons["Afficher ici"].click()
        XCTAssertTrue(shownElsewhere(in: second).waitForExistence(timeout: 3))
        XCTAssertTrue(shownElsewhere(in: first).waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testOpenInNewWindowThenMoveBackToTheSpace() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        openEmptyTab(in: app)
        let first = browserWindow(1, in: app)
        XCTAssertTrue(waitForCount(rows(in: first), 2))

        // The selected tab (at the top) leaves the sidebar for a window of its own, without favorites nor Spaces.
        rows(in: first).element(boundBy: 0).rightClick()
        let item = app.menuItems["Ouvrir dans une nouvelle fenêtre"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.click()
        let second = browserWindow(2, in: app)
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForCount(rows(in: second), 1))
        XCTAssertTrue(waitForCount(rows(in: first), 1))
        XCTAssertTrue(second.staticTexts["Cette fenêtre"].exists)

        // “Move to…”: the tab goes back into the Space, which the window now shows.
        second.descendants(matching: .any).matching(identifier: "moveWindowTabs").firstMatch.click()
        clickOpenMenuItem("Perso", in: app)
        XCTAssertTrue(waitForCount(rows(in: first), 2))
        XCTAssertTrue(waitForCount(rows(in: second), 2))
        XCTAssertFalse(second.staticTexts["Cette fenêtre"].exists)
    }
}
