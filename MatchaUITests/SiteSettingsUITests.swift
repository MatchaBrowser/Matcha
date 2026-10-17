import XCTest

/// Réglages du site (tâche 5.2) : bouton à côté de l'adresse, panneau sous la pastille ou en haut de la carte, caméra
/// et micro, effacement des données avec confirmation, liste des Réglages > Confidentialité. Le bandeau des demandes de
/// permission n'a pas de déclencheur sans réseau, et une vraie demande `getUserMedia` passe aussi par la demande d'accès
/// de macOS : il est couvert par les tests unitaires (`NavigationCoordinatorPermissionTests`) et à la main.
final class SiteSettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNoSiteSettingsOutsideAWebsite() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openAddress("about:blank?reglages", in: app)
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0.hasPrefix("about:blank") })
        XCTAssertFalse(siteSettingsButton(in: app).exists)
    }

    @MainActor
    func testSiteSettingsPanelInTheSidebar() throws {
        try skipIfOffline()
        let app = launchApp()
        checkSiteSettingsPanel(in: app)

        // La décision choisie figure dans Réglages > Confidentialité, d'où on peut l'oublier.
        app.typeKey(",", modifierFlags: .command)
        let privacy = app.toolbars.buttons["Confidentialité"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        privacy.click()
        let rows = app.descendants(matching: .any).matching(identifier: "sitePermissionRow")
        XCTAssertTrue(waitForCount(rows, 1))
        XCTAssertTrue(rows.firstMatch.staticTexts["example.com"].exists)
        rows.firstMatch.buttons["sitePermissionForgetButton"].click()
        XCTAssertTrue(waitForCount(rows, 0))
        XCTAssertTrue(app.staticTexts["Aucune décision enregistrée."].exists)
    }

    @MainActor
    func testSiteSettingsPanelAboveThePage() throws {
        try skipIfOffline()
        let app = launchApp(settings: ["addressBarPosition": "top"])
        checkSiteSettingsPanel(in: app)
    }

    /// Sur example.com : rien ne s'ouvre de soi-même ; le bouton ouvre le panneau (site, caméra et micro sur
    /// « Demander ») ; « Autoriser » est retenu ; « Effacer… » demande confirmation et « Annuler » n'efface rien ; la croix
    /// ferme le panneau et le bouton le rouvre puis le referme.
    @MainActor
    private func checkSiteSettingsPanel(in app: XCUIApplication) {
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openAddress("https://example.com", in: app)
        let button = siteSettingsButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        let panel = siteSettingsPanel(in: app)
        XCTAssertFalse(panel.exists)

        button.click()
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        // Un texte statique expose son texte dans sa valeur ; son libellé reste vide.
        XCTAssertEqual(panel.staticTexts["siteSettingsTitle"].value as? String, "example.com")
        let camera = permissionPicker(.camera, in: app)
        XCTAssertTrue(camera.exists)
        XCTAssertTrue(permissionPicker(.microphone, in: app).exists)
        XCTAssertEqual(camera.value as? String, "Demander")

        camera.click()
        app.menuItems["Autoriser"].click()
        XCTAssertTrue(waitForValue(of: camera) { $0 == "Autoriser" })

        panel.buttons["siteSettingsClearDataButton"].click()
        let sheetCancel = app.sheets.buttons["Annuler"].firstMatch
        let cancel = sheetCancel.waitForExistence(timeout: 3) ? sheetCancel : app.dialogs.buttons["Annuler"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 3))
        XCTAssertTrue(panel.exists)

        panel.buttons["siteSettingsCloseButton"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
        button.click()
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        XCTAssertEqual(permissionPicker(.camera, in: app).value as? String, "Autoriser")
        button.click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
    }
}
