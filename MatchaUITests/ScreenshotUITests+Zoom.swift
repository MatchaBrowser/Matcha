import XCTest

/// Screenshots of page zoom (task 5.4, `MATCHA_SCREENSHOT_ZOOM`, see `ScreenshotUITests`).
@MainActor
extension ScreenshotUITests {
    /// If `MATCHA_SCREENSHOT_ZOOM` is set: ⌘+ twice on the displayed tab, “125 %” badge next to the address pill
    /// captured once its animations are over (`31-zoom-badge`); without `MATCHA_SCREENSHOT_URLS`, the Postfix
    /// documentation is opened first (no network). Then, if `MATCHA_SCREENSHOT_ZOOM=site`, https://example.com
    /// (network) in a new tab, ⌘+ and the site settings panel opened on its “Zoom” row, “115 %” badge included
    /// (`32-zoom-reglages-site`). The zoom goes back to 100 % (⌘0) at the end.
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
            XCTFail("Site settings button not found: example.com needs the network")
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
