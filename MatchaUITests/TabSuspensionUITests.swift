import XCTest

/// Mémoire (tâche 5.6) : un onglet caché se met en veille sans changer dans la barre latérale, puis revient à sa page
/// avec son historique. Délai court donné au lancement (`tabSuspensionDelaySeconds`, Debug seulement) ; la valeur
/// d'accessibilité « suspended » d'une ligne d'onglet n'existe qu'en Debug. Pages : la documentation de Postfix livrée
/// avec macOS (sans réseau) ; test ignoré si elle manque. Ce test déplace la vraie souris.
final class TabSuspensionUITests: XCTestCase {
    private static let overviewPath = "/usr/share/doc/postfix/html/OVERVIEW.html"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHiddenTabIsSuspendedThenComesBackWithItsHistory() throws {
        let app = launchApp(settings: ["tabSuspensionDelaySeconds": "2"])
        XCTAssertTrue(waitForBrowserWindow(of: app))
        // Un onglet passé par l'accueil de la documentation puis « Basic configuration ».
        try visitLocalDocs(in: app)
        openAddress("file://" + Self.overviewPath, in: app)
        let overview = tabRow(titled: "Postfix Architecture Overview", in: app)
        XCTAssertTrue(overview.waitForExistence(timeout: 10))

        // Caché, l'onglet se met en veille ; sa ligne reste la même.
        let basic = tabRow(titled: "Postfix Basic Configuration", in: app)
        XCTAssertTrue(waitForValue(of: basic, timeout: 15) { $0 == "suspended" })
        XCTAssertEqual(basic.label, "Postfix Basic Configuration")
        XCTAssertEqual(tabRows(in: app).count, 2)
        // L'onglet affiché ne se met jamais en veille.
        XCTAssertNotEqual(overview.value as? String, "suspended")

        // Affiché de nouveau : même page, puis Précédent ramène à l'accueil de la documentation.
        basic.click()
        XCTAssertTrue(waitForValue(of: addressPill(in: app), timeout: 10) { $0 == "BASIC_CONFIGURATION_README.html" })
        XCTAssertTrue(waitUntilAwake(basic))
        XCTAssertEqual(tabRows(in: app).count, 2)
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(waitForValue(of: addressPill(in: app), timeout: 10) { $0 == "index.html" })
        XCTAssertTrue(tabRow(titled: "Postfix Documentation", in: app).waitForExistence(timeout: 10))
    }

    /// Attend que la ligne ne soit plus « suspended » (sans valeur, ou vide).
    @MainActor
    private func waitUntilAwake(_ row: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate { object, _ in
            ((object as? XCUIElement)?.value as? String) != "suspended"
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: row)], timeout: timeout) == .completed
    }
}
