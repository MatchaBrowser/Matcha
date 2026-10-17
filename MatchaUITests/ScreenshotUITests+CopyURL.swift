import XCTest

/// Capture de la confirmation « URL copiée » (tâche 4.6, `MATCHA_SCREENSHOT_COPY_URL`, voir `ScreenshotUITests`).
extension ScreenshotUITests {
    /// Confirmation « URL copiée » (⇧⌘C), capturée une fois le fondu d'apparition fini, puis attendue
    /// jusqu'à sa disparition pour ne pas gêner les captures suivantes.
    @MainActor
    func captureCopyConfirmation(in app: XCUIApplication, window: XCUIElement) {
        if ProcessInfo.processInfo.environment["MATCHA_SCREENSHOT_URLS"] == nil {
            openAddress("about:blank?copy", in: app)
        }
        app.typeKey("c", modifierFlags: [.command, .shift])
        let confirmation = app.descendants(matching: .any).matching(identifier: "copyConfirmation").firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        usleep(300_000)
        attach(window.screenshot(), as: "14-url-copiee")
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
    }
}
