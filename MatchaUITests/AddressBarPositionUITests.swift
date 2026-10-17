import XCTest

/// Barre d'adresse dans la barre latérale ou au-dessus de la page, boutons de navigation.
final class AddressBarPositionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddressBarAboveThePage() {
        let app = launchApp(settings: ["addressBarPosition": "top"])
        let window = app.windows.firstMatch
        let pill = addressPill(in: app)
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        // À droite de la barre latérale, qui garde ses onglets.
        XCTAssertGreaterThan(pill.frame.minX - window.frame.minX, 180)
        XCTAssertTrue(app.buttons["newTabButton"].exists)
        XCTAssertTrue(app.buttons["Précédent"].exists)

        // La pastille ouvre la barre de commande.
        pill.click()
        let field = addressField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        app.typeText("about:blank\n")
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(waitForValue(of: pill) { $0 == "about:blank" })
    }

    @MainActor
    func testHiddenSidebarKeepsTheAddressBarAboveThePage() {
        let app = launchApp(settings: ["addressBarPosition": "top"])
        let window = app.windows.firstMatch
        let field = addressField(in: app)
        XCTAssertTrue(waitForBrowserWindow(of: app))
        moveAwayFromLeftEdge(in: window)
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.buttons["newTabButton"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(addressPill(in: app).exists)

        // ⌘L ouvre la barre de commande sans faire apparaître la barre latérale.
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        XCTAssertFalse(app.buttons["newTabButton"].exists)
    }

    @MainActor
    func testNavigationButtonsCanBeHidden() {
        for position in ["sidebar", "top"] {
            let app = launchApp(settings: ["addressBarPosition": position, "showsNavigationButtons": "NO"])
            XCTAssertTrue(waitForBrowserWindow(of: app))
            XCTAssertFalse(app.buttons["Précédent"].exists, "position \(position)")
            XCTAssertFalse(app.buttons["Recharger"].exists, "position \(position)")
            app.terminate()
        }
    }
}
