import XCTest

/// Names of pinned tabs and favorites: renamed in the row or in an alert, given back to the page's title.
final class TabNameUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRenameAPinnedTabInItsRow() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Épingler"].click()
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Renommer"].click()
        let field = app.textFields["tabNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        app.typeText("Courrier\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).firstMatch.label, "Courrier")

        // Escape keeps the name.
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Renommer"].click()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).firstMatch.label, "Courrier")

        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Utiliser le titre de la page"].click()
        XCTAssertEqual(tabRows(in: app).firstMatch.label, "Nouvel onglet")
    }

    @MainActor
    func testRenameAFavoriteInAnAlert() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Ajouter aux favoris"].click()
        let favorite = app.descendants(matching: .any).matching(identifier: "favoriteTile").firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 3))

        favorite.rightClick()
        app.menuItems["Renommer…"].click()
        let nameField = app.dialogs.textFields.firstMatch.exists ? app.dialogs.textFields.firstMatch : app.sheets.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.typeKey("a", modifierFlags: .command)
        // Return confirms the alert (its default button is “Rename”).
        nameField.typeText("Agenda\n")
        XCTAssertTrue(nameField.waitForNonExistence(timeout: 3))
        XCTAssertEqual(favorite.label, "Agenda")
    }

    /// Settings > General, “Double-click a pinned tab or a favorite to rename it”: off, a double click only selects.
    @MainActor
    func testDoubleClickRenamesOnlyWithTheOption() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Épingler"].click()
        tabRows(in: app).firstMatch.doubleClick()
        XCTAssertFalse(app.textFields["tabNameField"].waitForExistence(timeout: 1))
        app.terminate()

        let withOption = launchApp(settings: ["renamesTabsOnDoubleClick": "YES"])
        XCTAssertTrue(waitForBrowserWindow(of: withOption))
        openEmptyTab(in: withOption)
        XCTAssertTrue(waitForCount(tabRows(in: withOption), 1))
        tabRows(in: withOption).firstMatch.rightClick()
        withOption.menuItems["Épingler"].click()
        tabRows(in: withOption).firstMatch.doubleClick()
        let field = withOption.textFields["tabNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        withOption.typeText("Courrier\n")
        XCTAssertEqual(tabRows(in: withOption).firstMatch.label, "Courrier")

        tabRows(in: withOption).firstMatch.rightClick()
        withOption.menuItems["Ajouter aux favoris"].click()
        let favorite = withOption.descendants(matching: .any).matching(identifier: "favoriteTile").firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 3))
        favorite.doubleClick()
        let alertField = withOption.dialogs.textFields.firstMatch.exists
            ? withOption.dialogs.textFields.firstMatch
            : withOption.sheets.textFields.firstMatch
        XCTAssertTrue(alertField.waitForExistence(timeout: 3))
    }
}
