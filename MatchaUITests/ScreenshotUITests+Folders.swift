import XCTest

/// Screenshots of a folder's customization (`MATCHA_SCREENSHOT_FOLDER`, see `ScreenshotUITests`).
@MainActor
extension ScreenshotUITests {
    /// If `MATCHA_SCREENSHOT_FOLDER` is set: pins an empty tab, creates a folder named after the value (“Projets” for
    /// “1”) and its subfolder “Client”; the folder gets the briefcase and an indigo background (readable text picked
    /// by the app), the subfolder the leaf and green text. Captures the panel open below the subfolder
    /// (`37-dossier-panneau`), then both rows, panel closed with its cross (`38-dossier-personnalise`).
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

    private func typeFolderName(_ name: String, in app: XCUIApplication) {
        let field = app.textFields["folderNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        app.typeText("\(name)\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }

    /// The folder's “Customize…”, then the given symbol and color swatches (nil: left untouched).
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
