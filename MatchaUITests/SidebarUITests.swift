import XCTest

/// Sidebar: layout, tab organization, drag and drop.
final class SidebarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddressPillStaysAtTheTopWithoutPage() {
        let app = launchApp()
        let pill = addressPill(in: app)
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch
        // Without a tab, then with an empty tab, the pill stays below the title bar, not in the middle.
        XCTAssertLessThan(pill.frame.minY - window.frame.minY, 120)
        openEmptyTab(in: app)
        XCTAssertLessThan(pill.frame.minY - window.frame.minY, 120)
    }

    @MainActor
    func testDraggingTheSidebarEdgeResizesItWithoutMovingTheWindow() {
        let app = launchApp()
        let window = app.windows.firstMatch
        let handle = app.descendants(matching: .any).matching(identifier: "sidebarResizeHandle").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let windowFrame = window.frame
        let startX = handle.frame.midX

        drag(handle, by: 60)
        XCTAssertEqual(window.frame, windowFrame)
        XCTAssertEqual(handle.frame.midX - startX, 60, accuracy: 2)

        // Width capped at 400 pt.
        drag(handle, by: 1000)
        XCTAssertEqual(handle.frame.midX - window.frame.minX, 400, accuracy: 2)

        // Restores the original width: it is remembered from one launch to the next.
        drag(handle, by: startX - handle.frame.midX)
        XCTAssertEqual(handle.frame.midX, startX, accuracy: 2)
    }

    @MainActor
    func testDraggingTheEmptyTopOfTheSidebarMovesTheWindow() {
        let app = launchApp()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let start = window.frame
        // Empty area below the title bar, right of the window buttons.
        let emptyArea = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 150, dy: 34))
        // Horizontal drag: vertically, macOS constrains the window (menu bar, snapping).
        emptyArea.press(forDuration: 0.2, thenDragTo: emptyArea.withOffset(CGVector(dx: 60, dy: 0)))
        // The window follows the gesture, give or take a small starting threshold.
        XCTAssertGreaterThan(window.frame.minX - start.minX, 20)
    }

    @MainActor
    func testFavoritesAndClearingTodayTabs() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        for _ in 0 ..< 3 {
            openEmptyTab(in: app)
        }
        XCTAssertTrue(waitForCount(tabRows(in: app), 3))

        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Ajouter aux favoris"].click()
        let favorites = app.descendants(matching: .any).matching(identifier: "favoriteTile")
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(tabRows(in: app).count, 2)

        clickWhenSettled(app.buttons["Effacer"])
        XCTAssertEqual(tabRows(in: app).count, 0)
        XCTAssertEqual(favorites.count, 1)
    }

    @MainActor
    func testDraggingTabsToFavoritesAndPinned() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        for _ in 0 ..< 3 {
            openEmptyTab(in: app)
        }
        XCTAssertTrue(waitForCount(tabRows(in: app), 3))

        let favoritesZone = app.descendants(matching: .any).matching(identifier: "favoritesDropZone").firstMatch
        tabRows(in: app).element(boundBy: 0).press(forDuration: 0.5, thenDragTo: favoritesZone)
        let favorites = app.descendants(matching: .any).matching(identifier: "favoriteTile")
        XCTAssertTrue(favorites.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 2)

        let pinnedZone = app.descendants(matching: .any).matching(identifier: "pinnedDropZone").firstMatch
        tabRows(in: app).element(boundBy: 1).press(forDuration: 0.5, thenDragTo: pinnedZone)
        // The pinned tab survives “Clear”, which only closes Today tabs.
        clickWhenSettled(app.buttons["Effacer"])
        XCTAssertTrue(waitForCount(tabRows(in: app), 1), "onglets restants : \(tabRows(in: app).count)")
        XCTAssertEqual(favorites.count, 1)
    }

    @MainActor
    func testNewTabButtonAddsTabs() {
        let app = launchApp()
        let newTabButton = app.buttons["newTabButton"]
        let field = addressField(in: app)
        XCTAssertTrue(newTabButton.waitForExistence(timeout: 5))
        // The button opens the command bar; Return without text creates the tab.
        newTabButton.click()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        XCTAssertEqual(tabRows(in: app).count, 0)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        newTabButton.click()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
    }

    @MainActor
    func testContextMenuDuplicatesAndClosesOtherTabs() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        for _ in 0 ..< 3 {
            openEmptyTab(in: app)
        }
        XCTAssertTrue(waitForCount(tabRows(in: app), 3))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Dupliquer"].click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 4))

        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Fermer les autres onglets"].click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
    }
}
