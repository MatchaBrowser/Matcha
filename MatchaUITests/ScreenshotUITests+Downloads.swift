import XCTest

/// Captures des téléchargements (`MATCHA_SCREENSHOT_DOWNLOADS`, voir `ScreenshotUITests`).
extension ScreenshotUITests {
    /// Si `MATCHA_SCREENSHOT_DOWNLOADS` est défini : le panneau vide, ouvert par le bouton du pied de la barre
    /// (`36-telechargements-vide`) ; puis télécharge ce fichier (chemin d'un fichier local que WebKit n'affiche pas, ou
    /// « 1 » pour celui des tests) et capture le bouton (`24-telechargement-bouton`) et la liste ouverte
    /// (`25-telechargements-liste`), refermée ensuite par sa croix. Le dossier de test est effacé à la fin
    /// (`removeDownloadsTestFolder`).
    @MainActor
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
