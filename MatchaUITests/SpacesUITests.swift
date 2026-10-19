import XCTest

/// Spaces: creation, switching from one to another, shared Favorites, renaming, deletion.
final class SpacesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func spaceButtons(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "spaceButton")
    }

    @MainActor
    func testEachSpaceHasItsOwnTabsAndControlNumbersSwitch() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))

        app.buttons["newSpaceButton"].click()
        XCTAssertTrue(waitForCount(spaceButtons(in: app), 2))
        XCTAssertTrue(waitForCount(tabRows(in: app), 0))

        app.typeKey("1", modifierFlags: .control)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        app.typeKey("2", modifierFlags: .control)
        XCTAssertTrue(waitForCount(tabRows(in: app), 0))
    }

    @MainActor
    func testFavoritesAreSharedBetweenSpacesOfTheProfile() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Ajouter aux favoris"].click()
        let favorites = app.descendants(matching: .any).matching(identifier: "favoriteTile")
        XCTAssertTrue(waitForCount(favorites, 1))

        app.buttons["newSpaceButton"].click()
        XCTAssertTrue(waitForCount(spaceButtons(in: app), 2))
        XCTAssertTrue(waitForCount(favorites, 1))
    }

    @MainActor
    func testRenameAndDeleteASpace() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        app.buttons["newSpaceButton"].click()
        XCTAssertTrue(waitForCount(spaceButtons(in: app), 2))

        spaceButtons(in: app).element(boundBy: 1).rightClick()
        app.menuItems["Renommer…"].click()
        let nameField = app.dialogs.textFields.firstMatch.exists ? app.dialogs.textFields.firstMatch : app.sheets.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.typeKey("a", modifierFlags: .command)
        // Return confirms the alert (its default button is “Rename”).
        nameField.typeText("Travail\n")
        XCTAssertTrue(app.descendants(matching: .any)["Space Travail"].waitForExistence(timeout: 3))

        spaceButtons(in: app).element(boundBy: 1).rightClick()
        app.menuItems["Supprimer le Space"].click()
        XCTAssertTrue(waitForCount(spaceButtons(in: app), 1))
    }
}
