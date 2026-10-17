import XCTest

/// Fenêtre de navigation privée (⇧⌘N).
final class PrivateWindowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPrivateWindowHasItsOwnTabsAndForgetsThem() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        let badge = app.descendants(matching: .any).matching(identifier: "privateBadge").firstMatch
        XCTAssertFalse(badge.exists)

        let privateWindow = openPrivateWindow(in: app)
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 2)
        // La fenêtre privée s'ouvre sans barre de commande, sur la page vide ; ⌘T l'ouvre dans cette
        // fenêtre, sans clic préalable.
        let hint = privateWindow.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Appuyez sur ⌘T")).firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 3))
        openEmptyTab(in: app, window: privateWindow)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        openEmptyTab(in: app, window: privateWindow)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        // ⌘W ferme un onglet, pas la fenêtre.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(badge.exists)

        // Fermer la fenêtre privée oublie ses onglets ; la suivante repart de zéro.
        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(badge.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForCount(tabRows(in: app), 0))
        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertEqual(tabRows(in: app).count, 0)
    }
}
