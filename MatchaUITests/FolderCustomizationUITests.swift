import XCTest

/// Personnalisation d'un dossier d'épinglés : panneau ouvert sous sa ligne par « Personnaliser… », symbole, couleurs
/// du texte et du fond, « Réinitialiser », fermeture par la croix, le menu ou Échap. En Debug, la valeur
/// d'accessibilité de la ligne résume son apparence (« symbol:star text:#FF3B30 background:#FFCC00 »).
final class FolderCustomizationUITests: XCTestCase {
    private static let defaultAppearance = "default text:none background:none"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCustomizeResetAndClose() {
        let app = launchApp()
        let folder = makeFolder(named: "Projets", in: app)
        XCTAssertEqual(folder.value as? String, Self.defaultAppearance)
        // Rien ne s'ouvre de soi-même.
        let panel = customizationPanel(in: app)
        XCTAssertFalse(panel.exists)

        openCustomization(of: folder, in: app)
        // Sous la ligne du dossier (une fois l'animation finie), avec son nom.
        sleep(1)
        XCTAssertGreaterThanOrEqual(panel.frame.minY, folder.frame.maxY - 1)
        XCTAssertEqual(panel.staticTexts["folderCustomizationTitle"].value as? String, "Projets")
        XCTAssertTrue(app.buttons["folderSymbol.folder"].isSelected)
        XCTAssertTrue(app.buttons["folderTextColor.none"].isSelected)
        XCTAssertFalse(app.buttons["folderAppearanceResetButton"].isEnabled)
        // Noms traduits pour VoiceOver.
        XCTAssertEqual(app.buttons["folderSymbol.star"].label, "Étoile")
        XCTAssertEqual(app.buttons["folderBackgroundColor.yellow"].label, "Jaune")

        clickWhenSettled(app.buttons["folderSymbol.star"])
        XCTAssertTrue(waitForValue(of: folder, timeout: 3) { $0 == "symbol:star text:none background:none" })
        XCTAssertTrue(app.buttons["folderSymbol.star"].isSelected)
        XCTAssertFalse(app.buttons["folderSymbol.folder"].isSelected)

        app.buttons["folderTextColor.red"].click()
        app.buttons["folderBackgroundColor.yellow"].click()
        XCTAssertTrue(waitForValue(of: folder, timeout: 3) { $0 == "symbol:star text:#FF3B30 background:#FFCC00" })
        XCTAssertTrue(app.buttons["folderTextColor.red"].isSelected)
        XCTAssertTrue(app.buttons["folderBackgroundColor.yellow"].isSelected)
        XCTAssertFalse(app.buttons["folderBackgroundColor.none"].isSelected)

        // « Aucune couleur » pour le texte : la couleur lisible sur le fond est choisie par l'app.
        app.buttons["folderTextColor.none"].click()
        XCTAssertTrue(waitForValue(of: folder, timeout: 3) { $0 == "symbol:star text:none background:#FFCC00" })

        app.buttons["folderAppearanceResetButton"].click()
        XCTAssertTrue(waitForValue(of: folder, timeout: 3) { $0 == Self.defaultAppearance })
        XCTAssertTrue(app.buttons["folderSymbol.folder"].isSelected)

        app.buttons["folderCustomizationCloseButton"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
        // L'apparence choisie reste quand le panneau se ferme.
        XCTAssertEqual(folder.value as? String, Self.defaultAppearance)
    }

    @MainActor
    func testMenuAndEscapeClose() {
        let app = launchApp()
        let folder = makeFolder(named: "Lectures", in: app)
        let panel = customizationPanel(in: app)

        openCustomization(of: folder, in: app)
        clickWhenSettled(app.buttons["folderSymbol.book"])
        XCTAssertTrue(waitForValue(of: folder, timeout: 3) { $0.hasPrefix("symbol:book ") })
        // Le menu du dossier ouvert propose de fermer le panneau.
        folder.rightClick()
        app.menuItems["Fermer la personnalisation"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
        XCTAssertEqual(folder.value as? String, "symbol:book text:none background:none")

        // Échap ferme le panneau, qui prend le clavier à l'ouverture.
        openCustomization(of: folder, in: app)
        sleep(1)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
    }

    /// Onglet vide épinglé, puis un dossier créé depuis lui et nommé `name`.
    @MainActor
    private func makeFolder(named name: String, in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Épingler"].click()
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Nouveau dossier"].click()
        let field = app.textFields["folderNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        app.typeText("\(name)\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        let folder = folderRow(in: app)
        XCTAssertEqual(folder.label, name)
        return folder
    }

    @MainActor
    private func openCustomization(of folder: XCUIElement, in app: XCUIApplication) {
        folder.rightClick()
        app.menuItems["Personnaliser…"].click()
        XCTAssertTrue(customizationPanel(in: app).waitForExistence(timeout: 3))
    }
}

extension XCTestCase {
    /// Première ligne de dossier de la barre.
    @MainActor
    func folderRow(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "folderRow").firstMatch
    }

    /// Panneau de personnalisation d'un dossier.
    @MainActor
    func customizationPanel(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "folderCustomizationPanel").firstMatch
    }
}
