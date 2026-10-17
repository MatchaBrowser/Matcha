import XCTest

/// Fenêtre de l'historique (tâche 5.5) : ⌘Y, lignes, recherche, effacement.
extension XCTestCase {
    /// Fenêtre « Historique ».
    @MainActor
    func historyWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows.matching(NSPredicate(format: "title == %@", "Historique")).firstMatch
    }

    /// ⌘Y : la fenêtre de l'historique s'ouvre (ou passe devant).
    @MainActor
    @discardableResult
    func openHistoryWindow(in app: XCUIApplication) -> XCUIElement {
        app.typeKey("y", modifierFlags: .command)
        let window = historyWindow(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        return window
    }

    /// Lignes de l'historique ; leur libellé est le titre de la page, leur valeur son domaine.
    @MainActor
    func historyRows(in scope: XCUIElement) -> XCUIElementQuery {
        scope.descendants(matching: .any).matching(identifier: "historyRow")
    }

    /// Ligne de l'historique dont le titre est exactement `title`.
    @MainActor
    func historyRow(titled title: String, in scope: XCUIElement) -> XCUIElement {
        historyRows(in: scope).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// Texte « Aucun historique » de la fenêtre vide.
    @MainActor
    func historyEmptyState(in scope: XCUIElement) -> XCUIElement {
        scope.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", "Aucun historique", "Aucun historique")).firstMatch
    }

    /// Bouton d'une alerte ou d'une feuille de l'app (le dialogue d'effacement peut être l'un ou l'autre).
    @MainActor
    func dialogButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let sheetButton = app.sheets.buttons[title].firstMatch
        return sheetButton.exists ? sheetButton : app.dialogs.buttons[title].firstMatch
    }

    /// Documentation de Postfix ouverte (sans réseau), puis sa page « Basic configuration » dans le même onglet :
    /// deux visites, « Postfix Documentation » et « Postfix Basic Configuration ».
    @MainActor
    func visitLocalDocs(in app: XCUIApplication) throws {
        try openLocalDocs(in: app)
        clickWhenSettled(link(containing: "Basic configuration", in: app))
        XCTAssertTrue(waitForValue(of: addressPill(in: app), timeout: 10) { $0 == "BASIC_CONFIGURATION_README.html" })
        XCTAssertTrue(tabRow(titled: "Postfix Basic Configuration", in: app).waitForExistence(timeout: 10))
    }
}
