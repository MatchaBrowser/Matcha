import XCTest

/// Screenshots of the site settings and the permission banner (task 5.2, see `ScreenshotUITests`).
@MainActor
extension ScreenshotUITests {
    /// If `MATCHA_SCREENSHOT_SITE_SETTINGS` is set: site settings panel opened on the displayed tab
    /// (`26-reglages-site`), then the data clearing confirmation (`27-reglages-site-effacer`), cancelled.
    /// Without `MATCHA_SCREENSHOT_URLS`, https://example.com is opened first (network needed).
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
            XCTFail("Site settings button not found: the displayed tab must be a website (http or https)")
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

    /// If `MATCHA_SCREENSHOT_PERMISSION_URL` is set: this page is opened, the page button named by
    /// `MATCHA_SCREENSHOT_PERMISSION_BUTTON` is clicked if it is set, then the camera or microphone request banner is
    /// captured (`28-permission-bandeau`), without answering. Network needed; if macOS hasn't given Matcha access to
    /// the camera yet, its own access request may appear and block the screenshot.
    func capturePermissionBanner(in app: XCUIApplication, window: XCUIElement) {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["MATCHA_SCREENSHOT_PERMISSION_URL"] else {
            return
        }
        openAddress(address, in: app)
        if let title = environment["MATCHA_SCREENSHOT_PERMISSION_BUTTON"] {
            let pageButton = app.webViews.buttons[title].firstMatch
            XCTAssertTrue(pageButton.waitForExistence(timeout: 20), "Button “\(title)” not found in the page")
            clickWhenSettled(pageButton)
        }
        let banner = app.descendants(matching: .any).matching(identifier: "permissionBanner").firstMatch
        guard banner.waitForExistence(timeout: 20) else {
            XCTFail("No permission banner")
            return
        }
        sleep(1)
        attach(window.screenshot(), as: "28-permission-bandeau")
    }
}
