import XCTest

/// Captures de la mini-fenêtre (`MATCHA_SCREENSHOT_MINI`, voir `ScreenshotUITests`).
extension ScreenshotUITests {
    /// Mini-fenêtre vide (barre ouverte), puis la page tapée, puis l'écran entier une fois la fenêtre du navigateur
    /// activée (la mini-fenêtre reste devant), enfin la page passée dans le Space (⌘O).
    @MainActor
    func captureMiniWindow(typing text: String, in app: XCUIApplication) {
        // Pas `app.windows.firstMatch` : la mini-fenêtre, devant, serait trouvée la première.
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
        // ⌘O vise la mini-fenêtre active : un clic dans sa page la rend active d'abord.
        mini.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).click()
        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(waitForCount(miniWindows(in: app), 0, timeout: 5))
        sleep(1)
        attach(browser.screenshot(), as: "23-mini-remise")
    }
}
