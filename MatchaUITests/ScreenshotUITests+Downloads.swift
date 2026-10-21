import XCTest

/// Screenshots of the downloads (`MATCHA_SCREENSHOT_DOWNLOADS`, see `ScreenshotUITests`).
@MainActor
extension ScreenshotUITests {
    /// If `MATCHA_SCREENSHOT_DOWNLOADS` is set: the empty panel, opened by the button in the sidebar footer
    /// (`36-telechargements-vide`); then downloads this file (path of a local file that WebKit doesn't display, or
    /// “1” for the one of the tests) and captures the button (`24-telechargement-bouton`) and the open list
    /// (`25-telechargements-liste`), then closed with its cross. The test folder is deleted at the end
    /// (`removeDownloadsTestFolder`).
    func captureDownloads(in app: XCUIApplication, window: XCUIElement) throws {
        guard let value = ProcessInfo.processInfo.environment["MATCHA_SCREENSHOT_DOWNLOADS"] else {
            return
        }
        let path = value == "1" ? try undisplayableFile() : value
        addTeardownBlock { @MainActor in
            self.removeDownloadsTestFolder()
        }
        let button = downloadsButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.click()
        XCTAssertTrue(downloadsEmptyState(in: app).waitForExistence(timeout: 3))
        sleep(1)
        attach(window.screenshot(), as: "36-telechargements-vide")
        clickWhenSettled(app.buttons["downloadsCloseButton"])
        XCTAssertTrue(downloadsPanel(in: app).waitForNonExistence(timeout: 3))

        download(path, in: app)
        sleep(2)
        attach(window.screenshot(), as: "24-telechargement-bouton")
        button.click()
        XCTAssertTrue(downloadRows(in: app).firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        attach(window.screenshot(), as: "25-telechargements-liste")
        clickWhenSettled(app.buttons["downloadsCloseButton"])
        XCTAssertTrue(downloadsPanel(in: app).waitForNonExistence(timeout: 3))
    }
}
