import XCTest

/// Captures de la recherche dans la page (`MATCHA_SCREENSHOT_FIND`, voir `ScreenshotUITests`).
extension ScreenshotUITests {
    /// Si `MATCHA_SCREENSHOT_FIND` est défini : ce texte est cherché (⌘F) dans l'onglet affiché, une occurrence
    /// trouvée (`29-recherche-trouvee`), puis « zzqqxx » (`30-recherche-introuvable`), et la barre se ferme (⎋). Sans
    /// `MATCHA_SCREENSHOT_URLS`, la documentation de Postfix livrée avec macOS est ouverte d'abord (sans réseau).
    @MainActor
    func captureFindBar(in app: XCUIApplication, window: XCUIElement) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let text = environment["MATCHA_SCREENSHOT_FIND"] else {
            return
        }
        if environment["MATCHA_SCREENSHOT_URLS"] == nil {
            try openLocalDocs(in: app)
            sleep(2)
        }
        openFindBar(in: app)
        app.typeText(text)
        sleep(1)
        attach(window.screenshot(), as: "29-recherche-trouvee")
        replaceFindText(with: "zzqqxx", in: app)
        XCTAssertTrue(waitForNotFound(in: app))
        sleep(1)
        attach(window.screenshot(), as: "30-recherche-introuvable")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(findField(in: app).waitForNonExistence(timeout: 3))
    }
}
