import XCTest

/// Memory (task 5.6): a hidden tab goes to sleep without changing in the sidebar, then comes back to its page
/// with its history. Short delay given at launch (`tabSuspensionDelaySeconds`, Debug only); the “suspended”
/// accessibility value of a tab row only exists in Debug. Pages: the stand-in of the Postfix documentation written
/// by the tests (`UITestPages`, no network). This test moves the real mouse.
final class TabSuspensionUITests: XCTestCase {
    private static let overviewPath = UITestPages.path("OVERVIEW.html")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHiddenTabIsSuspendedThenComesBackWithItsHistory() throws {
        let app = launchApp(settings: ["tabSuspensionDelaySeconds": "2"])
        XCTAssertTrue(waitForBrowserWindow(of: app))
        // A tab that went through the documentation home page then “Basic configuration”.
        try visitLocalDocs(in: app)
        openAddress("file://" + Self.overviewPath, in: app)
        let overview = tabRow(titled: "Postfix Architecture Overview", in: app)
        XCTAssertTrue(overview.waitForExistence(timeout: 10))

        // Hidden, the tab goes to sleep; its row stays the same.
        let basic = tabRow(titled: "Postfix Basic Configuration", in: app)
        XCTAssertTrue(waitForValue(of: basic, timeout: 15) { $0 == "suspended" })
        XCTAssertEqual(basic.label, "Postfix Basic Configuration")
        XCTAssertEqual(tabRows(in: app).count, 2)
        // The displayed tab never goes to sleep.
        XCTAssertNotEqual(overview.value as? String, "suspended")

        // Shown again: same page, then Back returns to the documentation home page.
        basic.click()
        XCTAssertTrue(waitForValue(of: addressPill(in: app), timeout: 10) { $0 == "BASIC_CONFIGURATION_README.html" })
        XCTAssertTrue(waitUntilAwake(basic))
        XCTAssertEqual(tabRows(in: app).count, 2)
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(waitForValue(of: addressPill(in: app), timeout: 10) { $0 == "index.html" })
        XCTAssertTrue(tabRow(titled: "Postfix Documentation", in: app).waitForExistence(timeout: 10))
    }

    /// Waits until the row is no longer “suspended” (no value, or empty).
    @MainActor
    private func waitUntilAwake(_ row: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate { object, _ in
            ((object as? XCUIElement)?.value as? String) != "suspended"
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: row)], timeout: timeout) == .completed
    }
}
