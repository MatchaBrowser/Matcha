import XCTest

/// Screenshots of the mini window (`MATCHA_SCREENSHOT_MINI`, see `ScreenshotUITests`).
@MainActor
extension ScreenshotUITests {
    /// Empty mini window (bar open), then the typed page, then the whole screen once the browser window is activated
    /// (the mini window stays in front), finally the page moved into the Space (⌘O).
    func captureMiniWindow(typing text: String, in app: XCUIApplication) {
        // Not `app.windows.firstMatch`: the mini window, in front, would be found first.
        let browser = browserWindow(in: app)
        let mini = openMiniWindow(in: app)
        sleep(1)
        attach(mini.screenshot(), as: "20-mini-vide")
        app.typeText("\(text)\n")
        sleep(4)
        attach(mini.screenshot(), as: "21-mini-page")
        uncoveredPoint(of: browser, avoiding: mini).click()
        sleep(1)
        attach(XCUIScreen.main.screenshot(), as: "22-mini-flottante")
        // ⌘O targets the active mini window: a click in its page makes it active first.
        mini.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).click()
        app.typeKey("o", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForCount(miniWindows(in: app), 0, timeout: 5))
        sleep(1)
        attach(browser.screenshot(), as: "23-mini-remise")
    }
}
