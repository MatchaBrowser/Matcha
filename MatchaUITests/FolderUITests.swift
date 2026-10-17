import XCTest

/// Dossiers d'épinglés : création, renommage, rangement, repli, imbrication.
final class FolderUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func folderRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "folderRow")
    }

    /// Crée un dossier par le menu `menuItem` de `element` et lui donne le nom `name`.
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

        // Le dossier est créé depuis l'onglet épinglé, puis nommé.
        let pinned = tabRows(in: app).firstMatch
        createFolder(named: "Travail", from: pinned, menuItem: "Nouveau dossier", in: app)
        let folder = folderRows(in: app).firstMatch
        XCTAssertEqual(folder.label, "Travail")

        // L'onglet épinglé, déposé au milieu de la ligne du dossier, y entre ; replier le dossier le cache.
        pinned.press(forDuration: 0.5, thenDragTo: folder)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        folder.click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        folder.click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))

        // Sous-dossier : replier le parent cache aussi le sous-dossier.
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
