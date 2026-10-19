import XCTest

/// Screenshot of the “URL Copied” confirmation (task 4.6, `MATCHA_SCREENSHOT_COPY_URL`, see `ScreenshotUITests`).
extension ScreenshotUITests {
    /// “URL Copied” confirmation (⇧⌘C), captured once the fade-in is over, then waited on until it goes away so it
    /// doesn't get in the way of the next screenshots.
    @MainActor
    func captureCopyConfirmation(in app: XCUIApplication, window: XCUIElement) {
        if ProcessInfo.processInfo.environment["MATCHA_SCREENSHOT_URLS"] == nil {
            openAddress("about:blank?copy", in: app)
        }
        app.typeKey("c", modifierFlags: [.command, .shift])
        let confirmation = app.descendants(matching: .any).matching(identifier: "copyConfirmation").firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        usleep(300_000)
        attach(window.screenshot(), as: "14-url-copiee")
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
    }
}
