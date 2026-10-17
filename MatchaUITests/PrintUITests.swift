import XCTest

/// Impression et export en PDF (tâche 5.4) : ⌘P ouvre la zone d'impression de macOS en feuille sur la fenêtre, et
/// « Exporter au format PDF… » la zone d'enregistrement, nommée d'après la page ; ⎋ les ferme sans rien imprimer ni
/// enregistrer. Page : la documentation de Postfix livrée avec macOS (sans réseau ; tests ignorés si elle manque). Ces
/// tests déplacent la vraie souris.
final class PrintUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchOnLocalDocs() throws -> XCUIApplication {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        try openLocalDocs(in: app)
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "index.html" })
        return app
    }

    @MainActor
    func testPrintOpensThePrintPanel() throws {
        let app = try launchOnLocalDocs()
        XCTAssertTrue(waitForMenuItem("Imprimer…", enabled: true, in: app))
        app.typeKey("p", modifierFlags: .command)
        let sheet = windowSheet(in: app)
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        XCTAssertTrue(sheet.buttons["Imprimer"].waitForExistence(timeout: 10))

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        // La page est toujours là, seule.
        XCTAssertEqual(tabRows(in: app).count, 1)
        XCTAssertEqual(addressPill(in: app).value as? String, "index.html")
    }

    @MainActor
    func testExportAsPDFOpensTheSavePanel() throws {
        let app = try launchOnLocalDocs()
        app.menuBars.menuBarItems["Fichier"].click()
        app.menuBars.menuItems["Exporter au format PDF…"].click()
        let sheet = windowSheet(in: app)
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        // La zone d'enregistrement d'une app sandboxée est dessinée par un autre processus : son champ du nom n'est
        // vérifié que s'il est exposé.
        let name = sheet.textFields.firstMatch
        if name.waitForExistence(timeout: 3) {
            XCTAssertEqual(name.value as? String, "Postfix Documentation.pdf")
        }

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertEqual(tabRows(in: app).count, 1)
    }
}
