import AppKit
import XCTest

/// Icône d'un Space : grille de symboles et emoji dans l'éditeur du Space (clic sur l'icône du Space affiché, ou
/// « Changer l'icône… » de son menu). En Debug, la valeur d'accessibilité du bouton d'un Space est son icône sous sa
/// forme enregistrée (« symbol:star.fill », « emoji:🌿 »).
final class SpaceIconUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPickASymbolThenAnEmoji() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        let space = spaceButtons(in: app).firstMatch
        XCTAssertTrue(space.waitForExistence(timeout: 5))
        XCTAssertEqual(space.value as? String, "symbol:circle.fill")

        space.click()
        let editor = spaceEditor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["spaceSymbol.circle.fill"].isSelected)
        // Noms traduits pour VoiceOver et les bulles.
        XCTAssertEqual(app.buttons["spaceSymbol.star.fill"].label, "Étoile")
        XCTAssertEqual(app.buttons["spaceSymbol.mountain.2.fill"].label, "Montagnes")

        clickWhenSettled(app.buttons["spaceSymbol.mountain.2.fill"])
        XCTAssertTrue(waitForValue(of: space, timeout: 3) { $0 == "symbol:mountain.2.fill" })
        XCTAssertTrue(app.buttons["spaceSymbol.mountain.2.fill"].isSelected)
        XCTAssertFalse(app.buttons["spaceSymbol.circle.fill"].isSelected)

        // Un emoji collé dans le champ remplace le symbole, qui n'est plus entouré.
        let field = app.textFields["spaceEmojiField"]
        field.click()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("🌿", forType: .string)
        field.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(waitForValue(of: space, timeout: 3) { $0 == "emoji:🌿" })
        XCTAssertFalse(app.buttons["spaceSymbol.mountain.2.fill"].isSelected)
        // Une lettre est refusée : le champ revient à l'emoji.
        field.typeText("a")
        XCTAssertTrue(waitForValue(of: field, timeout: 3) { $0 == "🌿" })
        XCTAssertEqual(space.value as? String, "emoji:🌿")
        // Champ vidé : le cercle, l'icône par défaut.
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(waitForValue(of: space, timeout: 3) { $0 == "symbol:circle.fill" })
        XCTAssertTrue(app.buttons["spaceSymbol.circle.fill"].isSelected)

        // Échap dans le champ ferme la bulle ; l'icône reste.
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(editor.waitForNonExistence(timeout: 3))
        XCTAssertEqual(space.value as? String, "symbol:circle.fill")
    }

    @MainActor
    func testContextMenuOpensTheEditorOfThatSpace() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        app.buttons["newSpaceButton"].click()
        XCTAssertTrue(waitForCount(spaceButtons(in: app), 2))
        let first = spaceButtons(in: app).element(boundBy: 0)
        let second = spaceButtons(in: app).element(boundBy: 1)
        XCTAssertEqual(second.value as? String, "symbol:star.fill")

        // Menu du premier Space, qui n'est plus affiché : plus de sous-menu des symboles.
        first.rightClick()
        XCTAssertTrue(app.menuItems["Changer l'icône…"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.menuItems["Icône"].exists)
        app.menuItems["Changer l'icône…"].click()
        let editor = spaceEditor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue(first.isSelected)
        XCTAssertTrue(app.buttons["spaceSymbol.circle.fill"].isSelected)

        clickWhenSettled(app.buttons["spaceSymbol.house.fill"])
        XCTAssertTrue(waitForValue(of: first, timeout: 3) { $0 == "symbol:house.fill" })
        XCTAssertEqual(second.value as? String, "symbol:star.fill")

        // Un clic à côté ferme la bulle.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).click()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 3))
        XCTAssertEqual(first.value as? String, "symbol:house.fill")
    }

    @MainActor
    private func spaceButtons(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "spaceButton")
    }

    @MainActor
    private func spaceEditor(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "spaceEditor").firstMatch
    }
}
