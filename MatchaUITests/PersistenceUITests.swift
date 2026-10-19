import XCTest

/// Saving tabs from one launch to the next, in a separate test store (“uitest”), which the app empties on the
/// test's first launch: the sandboxed test runner can't delete it.
final class PersistenceUITests: XCTestCase {
    private let settings = ["inMemoryStore": "NO", "storeName": "uitest"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPinnedTabSurvivesRelaunch() {
        var app = launchApp(settings: settings.merging(["resetStore": "YES"]) { _, new in new })
        XCTAssertTrue(waitForBrowserWindow(of: app))
        XCTAssertEqual(tabRows(in: app).count, 0)
        openAddress("about:blank", in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Épingler"].click()
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        // Batched save one second after the last change.
        sleep(3)
        app.terminate()

        app = launchApp(settings: settings)
        XCTAssertTrue(addressPill(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        XCTAssertTrue(tabRow(titled: "about:blank", in: app).exists)
        app.terminate()
    }

    /// Width share of the left pane of a two-pane split.
    @MainActor
    private func leftShare(in app: XCUIApplication) -> Double {
        let panes = orderedPagePanes(in: app)
        XCTAssertEqual(panes.count, 2)
        return panes[0].frame.width / (panes[0].frame.width + panes[1].frame.width)
    }

    @MainActor
    func testSplitSurvivesRelaunch() {
        var app = launchApp(settings: settings.merging(["resetStore": "YES"]) { _, new in new })
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openAddress("about:blank?one", in: app)
        openAddress("about:blank?two", in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        openInSplit("about:blank?one", in: app)
        XCTAssertTrue(waitForCount(pagePanes(in: app), 2))
        let divider = splitDivider(in: app)
        XCTAssertTrue(divider.waitForExistence(timeout: 2))
        drag(divider, by: -80)
        let share = leftShare(in: app)
        // Batched save one second after the last change.
        sleep(3)
        app.terminate()

        app = launchApp(settings: settings)
        XCTAssertTrue(addressPill(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForCount(splitRows(in: app), 1))
        XCTAssertTrue(waitForCount(pagePanes(in: app), 2))
        XCTAssertEqual(leftShare(in: app), share, accuracy: 0.02)
        app.terminate()
    }
}
