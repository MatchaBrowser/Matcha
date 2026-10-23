import XCTest

/// Top strip of the browser window, where its hidden title bar would be: a double click zooms the window.
final class WindowTitleBarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// In the margin above the page, then next to the window's buttons: the window zooms, and a second double click
    /// gives it its size back.
    @MainActor
    func testDoubleClickOnTheTopOfTheWindowZoomsIt() {
        let app = launchZoomingApp()
        let window = app.windows.firstMatch
        let initial = window.frame

        let aboveThePage = window.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0)).withOffset(CGVector(dx: 0, dy: 4))
        aboveThePage.doubleClick()
        XCTAssertTrue(waitForFrame(of: window) { $0.width > initial.width }, "Not zoomed: \(window.frame)")
        aboveThePage.doubleClick()
        XCTAssertTrue(waitForFrame(of: window) { $0 == initial }, "Size not given back: \(window.frame)")

        nextToTheWindowButtons(in: window).doubleClick()
        XCTAssertTrue(waitForFrame(of: window) { $0.width > initial.width }, "Not zoomed: \(window.frame)")
        nextToTheWindowButtons(in: window).doubleClick()
        XCTAssertTrue(waitForFrame(of: window) { $0 == initial }, "Size not given back: \(window.frame)")
    }

    /// Hidden sidebar shown by hovering the left edge: the top of its card zooms the window too.
    @MainActor
    func testDoubleClickOnTheTopOfTheFloatingSidebarZoomsTheWindow() {
        let app = launchZoomingApp()
        let window = app.windows.firstMatch
        let initial = window.frame
        let newTabButton = app.buttons["newTabButton"]
        moveAwayFromLeftEdge(in: window)
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(newTabButton.waitForNonExistence(timeout: 3))

        revealFloatingSidebar(in: window)
        XCTAssertTrue(newTabButton.waitForExistence(timeout: 3))
        nextToTheWindowButtons(in: window).doubleClick()
        XCTAssertTrue(waitForFrame(of: window) { $0.width > initial.width }, "Not zoomed: \(window.frame)")

        // The window has moved under the pointer: the sidebar is revealed again.
        revealFloatingSidebar(in: window)
        XCTAssertTrue(newTabButton.waitForExistence(timeout: 3))
        nextToTheWindowButtons(in: window).doubleClick()
        XCTAssertTrue(waitForFrame(of: window) { $0 == initial }, "Size not given back: \(window.frame)")
    }

    /// The user's choice in System Settings > Desktop & Dock doesn't change the result.
    @MainActor
    private func launchZoomingApp() -> XCUIApplication {
        let app = launchApp(settings: ["AppleActionOnDoubleClick": "Maximize"])
        XCTAssertTrue(waitForBrowserWindow(of: app))
        return app
    }

    /// Between the sidebar button and the navigation buttons, in the middle of the sidebar's top row (32 pt).
    @MainActor
    private func nextToTheWindowButtons(in window: XCUIElement) -> XCUICoordinate {
        window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 128, dy: 16))
    }

    @MainActor
    private func revealFloatingSidebar(in window: XCUIElement) {
        window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 3, dy: 0)).hover()
    }

    @MainActor
    private func waitForFrame(of window: XCUIElement, timeout: TimeInterval = 3, _ condition: @escaping (CGRect) -> Bool) -> Bool {
        let predicate = NSPredicate { object, _ in
            (object as? XCUIElement).map { condition($0.frame) } ?? false
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: window)], timeout: timeout) == .completed
    }
}
