import XCTest

/// Captures du zoom des pages (tâche 5.4, `MATCHA_SCREENSHOT_ZOOM`, voir `ScreenshotUITests`).
extension ScreenshotUITests {
    /// Si `MATCHA_SCREENSHOT_ZOOM` est défini : ⌘+ deux fois sur l'onglet affiché, badge « 125 % » à côté de la
    /// pastille d'adresse capturé une fois ses animations finies (`31-zoom-badge`) ; sans `MATCHA_SCREENSHOT_URLS`, la
    /// documentation de Postfix est ouverte d'abord (sans réseau). Puis, si `MATCHA_SCREENSHOT_ZOOM=site`,
    /// https://example.com (réseau) dans un nouvel onglet, ⌘+ et le panneau des réglages du site ouvert sur sa ligne
    /// « Zoom », badge « 115 % » compris (`32-zoom-reglages-site`). Le zoom revient à 100 % (⌘0) à la fin.
    @MainActor
    func captureZoom(in app: XCUIApplication, window: XCUIElement) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let mode = environment["MATCHA_SCREENSHOT_ZOOM"] else {
            return
        }
        if environment["MATCHA_SCREENSHOT_URLS"] == nil {
            try openLocalDocs(in: app)
            sleep(2)
        }
        app.typeKey("+", modifierFlags: .command)
        app.typeKey("+", modifierFlags: .command)
        XCTAssertTrue(waitForPercent(125, of: zoomBadge(in: app), inValue: true))
        usleep(500_000)
        attach(window.screenshot(), as: "31-zoom-badge")
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(zoomBadge(in: app).waitForNonExistence(timeout: 3))
        guard mode == "site" else {
            return
        }
        openAddress("https://example.com", in: app)
        let button = siteSettingsButton(in: app)
        guard button.waitForExistence(timeout: 20) else {
            XCTFail("Bouton des réglages du site introuvable : réseau nécessaire pour example.com")
            return
        }
        app.typeKey("+", modifierFlags: .command)
        button.click()
        XCTAssertTrue(siteZoomButton("siteZoomResetButton", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(waitForPercent(115, of: zoomBadge(in: app), inValue: true))
        usleep(500_000)
        attach(window.screenshot(), as: "32-zoom-reglages-site")
        app.typeKey("0", modifierFlags: .command)
        app.buttons["siteSettingsCloseButton"].click()
    }
}
