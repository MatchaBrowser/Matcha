import XCTest

/// Captures de l'import d'Arc (`MATCHA_SCREENSHOT_ARC`, voir `ScreenshotUITests`).
extension ScreenshotUITests {
    /// Si `MATCHA_SCREENSHOT_ARC` est défini : Fichier > Importer depuis > Arc…, le sélecteur ouvert sur le dossier d'Arc
    /// (`39-arc-selecteur`), puis le fichier donné (« 1 » : l'exemple inventé des tests unitaires) choisi par « Aller au
    /// dossier » : l'aperçu (`40-arc-apercu`), et la fenêtre après « Importer » (`41-arc-importe`).
    @MainActor
    func captureArcImport(in app: XCUIApplication, window: XCUIElement) {
        guard let value = ProcessInfo.processInfo.environment["MATCHA_SCREENSHOT_ARC"] else {
            return
        }
        let path = value == "1" ? Self.arcSamplePath : value
        app.menuBars.menuBarItems["Fichier"].click()
        app.menuBars.menuItems["Importer depuis"].hover()
        app.menuBars.menuItems["Arc…"].click()
        sleep(2)
        attach(window.screenshot(), as: "39-arc-selecteur")
        app.typeKey("g", modifierFlags: [.command, .shift])
        sleep(1)
        app.typeText(path)
        app.typeKey(.return, modifierFlags: [])
        sleep(1)
        app.typeKey(.return, modifierFlags: [])
        let title = app.descendants(matching: .any)["arcImportTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        sleep(1)
        attach(window.screenshot(), as: "40-arc-apercu")
        app.buttons["arcImportButton"].click()
        sleep(2)
        attach(window.screenshot(), as: "41-arc-importe")
    }

    /// Exemple inventé des tests unitaires, lu dans les sources.
    private static var arcSamplePath: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "MatchaTests/Fixtures/arc-sidebar-sample.json").path
    }
}
