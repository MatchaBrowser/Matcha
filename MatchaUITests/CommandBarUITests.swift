import XCTest

/// Barre de commande (⌘T, ⌘L) : ouverture, fermeture, lignes et clavier. Hors ligne : les onglets se
/// distinguent par `about:blank?…` (WebKit réécrit `#` en `%23`).
final class CommandBarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func spaceButtons(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "spaceButton")
    }

    /// Ligne de la barre dont le titre est exactement `title`.
    @MainActor
    private func commandBarRow(titled title: String, in scope: XCUIElement) -> XCUIElement {
        commandBarRows(in: scope).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// Lance l'app (aucun onglet, barre fermée) et attend sa fenêtre.
    @MainActor
    private func launch() -> XCUIApplication {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        return app
    }

    /// Lance l'app, ouvre la barre (⌘T) et attend que son champ ait le clavier.
    @MainActor
    private func launchAndOpenBar() -> (app: XCUIApplication, field: XCUIElement) {
        let app = launch()
        return (app, openCommandBar(in: app))
    }

    @MainActor
    func testEscapeLeavesNoTab() {
        let (app, field) = launchAndOpenBar()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 0)
    }

    @MainActor
    func testReturnWithoutTextOpensAnEmptyTab() {
        let app = launch()
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertFalse(addressField(in: app).exists)
    }

    @MainActor
    func testTypedAddressOpensInANewTab() {
        let (app, _) = launchAndOpenBar()
        app.typeText("about:blank?one")
        let first = commandBarRows(in: app).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(first.label.contains("about:blank?one"), first.label)

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "about:blank?one" })
    }

    @MainActor
    func testCommandLEditsTheShownTab() {
        let app = launch()
        openAddress("about:blank?one", in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))

        // L'URL complète, sélectionnée : ligne de l'adresse puis « Copier l'URL ».
        let field = openCommandBar(in: app, newTab: false)
        XCTAssertTrue(waitForValue(of: field) { $0 == "about:blank?one" })
        let rows = commandBarRows(in: app)
        XCTAssertTrue(waitForCount(rows, 2))
        XCTAssertEqual(rows.element(boundBy: 1).label, "Copier l'URL")

        // La frappe remplace l'adresse ; elle s'ouvre dans le même onglet.
        app.typeText("about:blank?two\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "about:blank?two" })
        XCTAssertEqual(tabRows(in: app).count, 1)
    }

    @MainActor
    func testArrowsAndReturnSwitchToAnOpenTab() {
        let app = launch()
        openAddress("about:blank?one", in: app)
        openAddress("about:blank?two", in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))

        // « blank » : la recherche, puis l'onglet ?one (l'onglet affiché n'est pas proposé).
        let field = openCommandBar(in: app)
        app.typeText("blank")
        let rows = commandBarRows(in: app)
        XCTAssertTrue(waitForCount(rows, 2))

        // La sélection ne boucle pas.
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(rows.element(boundBy: 0).isSelected)
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(rows.element(boundBy: 1).isSelected)
        XCTAssertFalse(rows.element(boundBy: 0).isSelected)

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "about:blank?one" })
        XCTAssertEqual(tabRows(in: app).count, 2)
    }

    @MainActor
    func testCommandWClosesOnlyTheBar() {
        let app = launch()
        openAddress("about:blank?one", in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))

        let field = openCommandBar(in: app)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 1)
    }

    @MainActor
    func testClickingOutsideClosesTheBarAndReachesTheTarget() {
        let app = launch()
        openAddress("about:blank?one", in: app)
        openAddress("about:blank?two", in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))

        let field = openCommandBar(in: app)
        // Le clic ferme la barre et sélectionne l'onglet, du premier coup.
        tabRow(titled: "about:blank?one", in: app).click()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "about:blank?one" })
    }

    @MainActor
    func testSwitchingSpaceClosesTheBar() {
        let app = launch()
        app.buttons["newSpaceButton"].click()
        XCTAssertTrue(waitForCount(spaceButtons(in: app), 2))
        let field = openCommandBar(in: app)
        app.typeText("swift")
        // ⌃1 : le menu Spaces passe au premier Space ; la barre se ferme sans rien ouvrir.
        app.typeKey("1", modifierFlags: .control)
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 0)
    }

    @MainActor
    func testNewSpaceAction() {
        let (app, _) = launchAndOpenBar()
        app.typeText("space")
        let row = commandBarRow(titled: "Nouveau Space", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        XCTAssertTrue(waitForCount(spaceButtons(in: app), 2))
    }

    @MainActor
    func testSettingsAction() {
        let (app, _) = launchAndOpenBar()
        app.typeText("réglages")
        let row = commandBarRow(titled: "Réglages", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        XCTAssertTrue(waitForCount(app.windows, 2, timeout: 5))

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(app.windows, 1))
    }

    @MainActor
    func testPrivateWindowHasNoNewSpaceAction() {
        let app = launch()
        let privateWindow = openPrivateWindow(in: app)
        openCommandBar(in: app, window: privateWindow)

        app.typeText("space")
        XCTAssertFalse(commandBarRow(titled: "Nouveau Space", in: privateWindow).waitForExistence(timeout: 1))
        // Seule la recherche du texte reste.
        XCTAssertEqual(commandBarRows(in: privateWindow).count, 1)
    }
}
