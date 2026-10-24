import XCTest

/// Profiles (settings) and moving tabs between Spaces.
final class ProfilesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func spaceButtons(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "spaceButton")
    }

    @MainActor
    func testCreateAndDeleteAProfileFromSettings() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        app.typeKey(",", modifierFlags: .command)
        let profilesTab = app.toolbars.buttons["Profils"]
        XCTAssertTrue(profilesTab.waitForExistence(timeout: 5))
        profilesTab.click()
        let rows = app.textFields.matching(identifier: "profileNameField")
        XCTAssertTrue(waitForCount(rows, 1))

        app.buttons["newProfileButton"].click()
        XCTAssertTrue(waitForCount(rows, 2))
        XCTAssertTrue(waitForCount(spaceButtons(in: app), 2))

        app.buttons.matching(NSPredicate(format: "label == %@", "Supprimer le profil")).element(boundBy: 1).click()
        // The button of the confirmation sheet (a duplicate exists in the Touch Bar).
        let sheetConfirm = app.sheets.buttons["Supprimer"].firstMatch
        let confirm = sheetConfirm.waitForExistence(timeout: 3) ? sheetConfirm : app.dialogs.buttons["Supprimer"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.click()
        XCTAssertTrue(waitForCount(rows, 1))
        XCTAssertTrue(waitForCount(spaceButtons(in: app), 1))
    }

    @MainActor
    func testMoveATabToAnotherSpace() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        createSpace(in: app)
        XCTAssertTrue(waitForCount(spaceButtons(in: app), 2))
        app.typeKey("1", modifierFlags: .control)
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))

        tabRows(in: app).firstMatch.rightClick()
        let moveMenu = app.menuItems["Déplacer vers"]
        moveMenu.hover()
        // “Space 2” also exists in the Spaces menu of the menu bar.
        moveMenu.menuItems["Space 2"].click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 0))
        app.typeKey("2", modifierFlags: .control)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
    }
}
