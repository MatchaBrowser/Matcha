import XCTest

/// Site settings (task 5.2): button next to the address, panel below the pill or at the top of the card, camera
/// and microphone, data clearing with confirmation, list in Settings > Privacy. The permission request banner
/// has no trigger without network, and a real `getUserMedia` request also goes through the macOS access request:
/// it is covered by the unit tests (`NavigationCoordinatorPermissionTests`) and by hand.
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

        // The chosen decision appears in Settings > Privacy, where it can be forgotten.
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

    /// On example.com: nothing opens by itself; the button opens the panel (site, camera and microphone on
    /// “Ask”); “Allow” is remembered; “Clear…” asks for confirmation and “Cancel” clears nothing; the cross
    /// closes the panel and the button reopens it then closes it again.
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
        // A static text exposes its text in its value; its label stays empty.
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
