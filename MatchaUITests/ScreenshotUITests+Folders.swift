import XCTest

/// Captures de la personnalisation d'un dossier (`MATCHA_SCREENSHOT_FOLDER`, voir `ScreenshotUITests`).
extension ScreenshotUITests {
    /// Si `MATCHA_SCREENSHOT_FOLDER` est défini : épingle un onglet vide, crée un dossier nommé d'après la valeur
    /// (« Projets » pour « 1 ») et son sous-dossier « Client » ; le dossier prend le porte-documents et un fond indigo (texte
    /// lisible choisi par l'app), le sous-dossier la feuille et un texte vert. Capture le panneau ouvert sous le
    /// sous-dossier (`37-dossier-panneau`), puis les deux lignes, panneau fermé par sa croix (`38-dossier-personnalise`).
    @MainActor
    func captureFolderCustomization(in app: XCUIApplication, window: XCUIElement) {
        guard let value = ProcessInfo.processInfo.environment["MATCHA_SCREENSHOT_FOLDER"] else {
            return
        }
        let name = value == "1" ? "Projets" : value
        openEmptyTab(in: app)
        let tab = tabRows(in: app).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 3))
        tab.rightClick()
        app.menuItems["Épingler"].click()
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Nouveau dossier"].click()
        typeFolderName(name, in: app)
        let folder = app.descendants(matching: .any).matching(identifier: "folderRow").matching(NSPredicate(format: "label == %@", name))
            .firstMatch
        customize(folder, symbol: "briefcase", textColor: nil, backgroundColor: "indigo", in: app)
        clickWhenSettled(app.buttons["folderCustomizationCloseButton"])

        folder.rightClick()
        app.menuItems["Nouveau sous-dossier"].click()
        typeFolderName("Client", in: app)
        let child = app.descendants(matching: .any).matching(identifier: "folderRow").matching(NSPredicate(format: "label == %@", "Client"))
            .firstMatch
        customize(child, symbol: "leaf", textColor: "green", backgroundColor: nil, in: app)
        sleep(1)
        attach(window.screenshot(), as: "37-dossier-panneau")
        clickWhenSettled(app.buttons["folderCustomizationCloseButton"])
        XCTAssertTrue(customizationPanel(in: app).waitForNonExistence(timeout: 3))
        moveAwayFromLeftEdge(in: window)
        sleep(1)
        attach(window.screenshot(), as: "38-dossier-personnalise")
    }

    @MainActor
    private func typeFolderName(_ name: String, in app: XCUIApplication) {
        let field = app.textFields["folderNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        app.typeText("\(name)\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }

    /// « Personnaliser… » du dossier, puis le symbole et les pastilles de couleur donnés (nil : sans y toucher).
    @MainActor
    private func customize(_ folder: XCUIElement, symbol: String, textColor: String?, backgroundColor: String?, in app: XCUIApplication) {
        folder.rightClick()
        app.menuItems["Personnaliser…"].click()
        XCTAssertTrue(customizationPanel(in: app).waitForExistence(timeout: 3))
        clickWhenSettled(app.buttons["folderSymbol.\(symbol)"])
        if let textColor {
            app.buttons["folderTextColor.\(textColor)"].click()
        }
        if let backgroundColor {
            app.buttons["folderBackgroundColor.\(backgroundColor)"].click()
        }
    }
}
