import XCTest

/// Screenshots of the history window (task 5.5, `MATCHA_SCREENSHOT_HISTORY`, see `ScreenshotUITests`).
extension ScreenshotUITests {
    /// If `MATCHA_SCREENSHOT_HISTORY` is set: without `MATCHA_SCREENSHOT_URLS`, two pages of the Postfix
    /// documentation are visited first (no network); then ⌘Y, the history window (`33-historique`); with a value other
    /// than “1”, this text searched (`34-historique-recherche`); finally the “Clear History…” dialog
    /// (`35-historique-effacer`), cancelled, and the window closed (⌘W).
    @MainActor
    func captureHistory(in app: XCUIApplication) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let search = environment["MATCHA_SCREENSHOT_HISTORY"] else {
            return
        }
        if environment["MATCHA_SCREENSHOT_URLS"] == nil {
            try visitLocalDocs(in: app)
        }
        let window = openHistoryWindow(in: app)
        XCTAssertTrue(historyRows(in: window).firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        attach(window.screenshot(), as: "33-historique")
        if search != "1" {
            let field = window.searchFields.firstMatch
            field.click()
            field.typeText(search)
            sleep(1)
            attach(window.screenshot(), as: "34-historique-recherche")
            field.typeKey("a", modifierFlags: .command)
            field.typeKey(.delete, modifierFlags: [])
        }
        window.buttons["historyClearButton"].click()
        let cancel = dialogButton("Annuler", in: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        sleep(1)
        attach(window.screenshot(), as: "35-historique-effacer")
        cancel.click()
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(window.waitForNonExistence(timeout: 5))
    }
}
