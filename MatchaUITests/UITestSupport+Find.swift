import XCTest

/// Recherche dans la page (tâche 5.3) : barre, champ et résultat.
extension XCTestCase {
    /// Champ de la barre de recherche ; sa valeur est le texte cherché.
    @MainActor
    func findField(in app: XCUIApplication) -> XCUIElement {
        app.textFields["findField"].firstMatch
    }

    /// « Introuvable », affiché au bout du champ quand la dernière recherche n'a rien trouvé.
    @MainActor
    func findStatus(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "findStatus").firstMatch
    }

    /// Bouton de la barre : `findPreviousButton`, `findNextButton`, `findCloseButton`.
    @MainActor
    func findButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons[identifier].firstMatch
    }

    /// ⌘F : la barre s'ouvre (ou reste ouverte) et son champ prend le clavier.
    @MainActor
    @discardableResult
    func openFindBar(in app: XCUIApplication) -> XCUIElement {
        app.typeKey("f", modifierFlags: .command)
        let field = findField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        return field
    }

    /// Le champ a le clavier : ⌘A puis `text`, qui remplace le texte cherché.
    @MainActor
    func replaceFindText(with text: String, in app: XCUIApplication) {
        app.typeKey("a", modifierFlags: .command)
        app.typeText(text)
    }

    /// « Introuvable » est affiché (texte ou valeur de l'élément, selon ce que SwiftUI expose).
    @MainActor
    func waitForNotFound(in app: XCUIApplication, timeout: TimeInterval = 3) -> Bool {
        let status = findStatus(in: app)
        guard status.waitForExistence(timeout: timeout) else {
            return false
        }
        return status.label == "Introuvable" || status.value as? String == "Introuvable"
    }
}
