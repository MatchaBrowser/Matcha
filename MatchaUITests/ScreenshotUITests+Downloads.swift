import XCTest

/// Captures des téléchargements (`MATCHA_SCREENSHOT_DOWNLOADS`, voir `ScreenshotUITests`).
extension ScreenshotUITests {
    /// Si `MATCHA_SCREENSHOT_DOWNLOADS` est défini, télécharge ce fichier (chemin d'un fichier local que WebKit
    /// n'affiche pas, ou « 1 » pour celui des tests), puis capture le bouton apparu dans le pied de la barre
    /// (`24-telechargement-bouton`) et la liste ouverte (`25-telechargements-liste`). Le dossier de test est effacé
    /// à la fin (`removeDownloadsTestFolder`).
    @MainActor
    func captureDownloads(in app: XCUIApplication, window: XCUIElement) throws {
        guard let value = ProcessInfo.processInfo.environment["MATCHA_SCREENSHOT_DOWNLOADS"] else {
            return
        }
        let path = value == "1" ? try undisplayableFile() : value
        addTeardownBlock { @MainActor in
            self.removeDownloadsTestFolder()
        }
        download(path, in: app)
        let button = downloadsButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        sleep(1)
        attach(window.screenshot(), as: "24-telechargement-bouton")
        button.click()
        XCTAssertTrue(downloadsPopover(in: app).waitForExistence(timeout: 3))
        sleep(1)
        attach(window.screenshot(), as: "25-telechargements-liste")
        app.typeKey(.escape, modifierFlags: [])
    }
}
