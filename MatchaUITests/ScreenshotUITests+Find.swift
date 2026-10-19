import XCTest

/// Screenshots of find in page (`MATCHA_SCREENSHOT_FIND`, see `ScreenshotUITests`).
extension ScreenshotUITests {
    /// If `MATCHA_SCREENSHOT_FIND` is set: this text is searched (⌘F) in the displayed tab, one match found
    /// (`29-recherche-trouvee`), then “zzqqxx” (`30-recherche-introuvable`), and the bar closes (⎋). Without
    /// `MATCHA_SCREENSHOT_URLS`, the Postfix documentation shipped with macOS is opened first (no network).
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
