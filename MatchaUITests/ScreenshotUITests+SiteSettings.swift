import XCTest

/// Captures des réglages du site et du bandeau de permission (tâche 5.2, voir `ScreenshotUITests`).
extension ScreenshotUITests {
    /// Si `MATCHA_SCREENSHOT_SITE_SETTINGS` est défini : panneau des réglages du site ouvert sur l'onglet affiché
    /// (`26-reglages-site`), puis la confirmation de l'effacement des données (`27-reglages-site-effacer`), annulée.
    /// Sans `MATCHA_SCREENSHOT_URLS`, https://example.com est ouvert d'abord (réseau nécessaire).
    @MainActor
    func captureSiteSettings(in app: XCUIApplication, window: XCUIElement) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MATCHA_SCREENSHOT_SITE_SETTINGS"] != nil else {
            return
        }
        if environment["MATCHA_SCREENSHOT_URLS"] == nil {
            openAddress("https://example.com", in: app)
        }
        let button = siteSettingsButton(in: app)
        guard button.waitForExistence(timeout: 20) else {
            XCTFail("Bouton des réglages du site introuvable : l'onglet affiché doit être un site web (http ou https)")
            return
        }
        button.click()
        sleep(1)
        attach(window.screenshot(), as: "26-reglages-site")
        app.buttons["siteSettingsClearDataButton"].click()
        sleep(1)
        attach(window.screenshot(), as: "27-reglages-site-effacer")
        let sheetCancel = app.sheets.buttons["Annuler"].firstMatch
        (sheetCancel.exists ? sheetCancel : app.dialogs.buttons["Annuler"].firstMatch).click()
        app.buttons["siteSettingsCloseButton"].click()
    }

    /// Si `MATCHA_SCREENSHOT_PERMISSION_URL` est défini : cette page est ouverte, le bouton de la page nommé par
    /// `MATCHA_SCREENSHOT_PERMISSION_BUTTON` est cliqué s'il est défini, puis le bandeau de la demande de caméra ou de
    /// micro est capturé (`28-permission-bandeau`), sans réponse. Réseau nécessaire ; si macOS n'a pas encore donné
    /// l'accès à la caméra à Matcha, sa propre demande d'accès peut apparaître et bloquer la capture.
    @MainActor
    func capturePermissionBanner(in app: XCUIApplication, window: XCUIElement) {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["MATCHA_SCREENSHOT_PERMISSION_URL"] else {
            return
        }
        openAddress(address, in: app)
        if let title = environment["MATCHA_SCREENSHOT_PERMISSION_BUTTON"] {
            let pageButton = app.webViews.buttons[title].firstMatch
            XCTAssertTrue(pageButton.waitForExistence(timeout: 20), "Bouton « \(title) » introuvable dans la page")
            clickWhenSettled(pageButton)
        }
        let banner = app.descendants(matching: .any).matching(identifier: "permissionBanner").firstMatch
        guard banner.waitForExistence(timeout: 20) else {
            XCTFail("Aucun bandeau de permission")
            return
        }
        sleep(1)
        attach(window.screenshot(), as: "28-permission-bandeau")
    }
}
