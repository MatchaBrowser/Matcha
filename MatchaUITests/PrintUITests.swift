import XCTest

/// Printing and PDF export (task 5.4): ⌘P opens the macOS print panel as a sheet on the window, and “Export as
/// PDF…” the save panel, named after the page; ⎋ closes them without printing or saving anything. Page: the
/// stand-in of the Postfix documentation written by the tests (`UITestPages`, no network). These tests move the
/// real mouse.
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
        // The page is still there, alone.
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
        // The save panel of a sandboxed app is drawn by another process: its name field is only checked if it is
        // exposed.
        let name = sheet.textFields.firstMatch
        if name.waitForExistence(timeout: 3) {
            XCTAssertEqual(name.value as? String, "Postfix Documentation.pdf")
        }

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertEqual(tabRows(in: app).count, 1)
    }
}
