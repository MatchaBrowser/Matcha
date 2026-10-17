import XCTest

/// Captures de la fenêtre de l'historique (tâche 5.5, `MATCHA_SCREENSHOT_HISTORY`, voir `ScreenshotUITests`).
extension ScreenshotUITests {
    /// Si `MATCHA_SCREENSHOT_HISTORY` est défini : sans `MATCHA_SCREENSHOT_URLS`, deux pages de la documentation de
    /// Postfix sont visitées d'abord (sans réseau) ; puis ⌘Y, la fenêtre de l'historique (`33-historique`) ; avec une
    /// valeur autre que « 1 », ce texte cherché (`34-historique-recherche`) ; enfin le dialogue « Effacer
    /// l'historique… » (`35-historique-effacer`), annulé, et la fenêtre fermée (⌘W).
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
