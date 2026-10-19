import XCTest

/// Pinned folders: creation, renaming, filing, collapsing, nesting.
final class FolderUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func folderRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "folderRow")
    }

    /// Creates a folder through the `menuItem` menu item of `element` and names it `name`.
    @MainActor
    private func createFolder(named name: String, from element: XCUIElement, menuItem: String, in app: XCUIApplication) {
        element.rightClick()
        app.menuItems[menuItem].click()
        let field = app.textFields["folderNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        app.typeText("\(name)\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testCreateFillCollapseAndNestFolders() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Épingler"].click()

        // The folder is created from the pinned tab, then named.
        let pinned = tabRows(in: app).firstMatch
        createFolder(named: "Travail", from: pinned, menuItem: "Nouveau dossier", in: app)
        let folder = folderRows(in: app).firstMatch
        XCTAssertEqual(folder.label, "Travail")

        // The pinned tab, dropped on the middle of the folder row, goes into it; collapsing the folder hides it.
        pinned.press(forDuration: 0.5, thenDragTo: folder)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        folder.click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        folder.click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))

        // Subfolder: collapsing the parent also hides the subfolder.
        createFolder(named: "Client", from: folder, menuItem: "Nouveau sous-dossier", in: app)
        XCTAssertTrue(waitForCount(folderRows(in: app), 2))
        folder.click()
        XCTAssertTrue(waitForCount(folderRows(in: app), 1))
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
    }

    @MainActor
    func testEscapeKeepsTheDefaultName() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Épingler"].click()
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Nouveau dossier"].click()
        let field = app.textFields["folderNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertEqual(folderRows(in: app).firstMatch.label, "Nouveau dossier")
    }
}
