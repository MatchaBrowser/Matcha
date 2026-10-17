import XCTest

/// Enregistrement des onglets d'un lancement à l'autre, dans une base de test à part (« uitest »), que
/// l'app vide au premier lancement du test : le lanceur des tests, sandboxé, ne peut pas la supprimer.
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
        // Enregistrement groupé une seconde après le dernier changement.
        sleep(3)
        app.terminate()

        app = launchApp(settings: settings)
        XCTAssertTrue(addressPill(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        XCTAssertTrue(tabRow(titled: "about:blank", in: app).exists)
        app.terminate()
    }
}
