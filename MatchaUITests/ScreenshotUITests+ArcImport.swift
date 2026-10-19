import XCTest

/// Screenshots of the Arc import (`MATCHA_SCREENSHOT_ARC`, see `ScreenshotUITests`).
extension ScreenshotUITests {
    /// If `MATCHA_SCREENSHOT_ARC` is set: File > Import From > Arc…, the picker opened on Arc's folder
    /// (`39-arc-selecteur`), then the given file (“1”: the made-up example of the unit tests) chosen with “Go to
    /// Folder”: the preview (`40-arc-apercu`), and the window after “Import” (`41-arc-importe`).
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

    /// Made-up example of the unit tests, read from the sources.
    private static var arcSamplePath: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "MatchaTests/Fixtures/arc-sidebar-sample.json").path
    }
}
