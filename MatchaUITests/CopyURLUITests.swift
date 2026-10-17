import AppKit
import XCTest

/// Copier l'URL (⇧⌘C, action de la barre de commande, menu contextuel) : l'adresse arrive dans le
/// presse-papiers et la confirmation « URL copiée » apparaît puis disparaît d'elle-même. Hors ligne :
/// `about:blank?copy`. Ces tests écrivent dans le presse-papiers général ; son contenu est vérifié par
/// un collage (⌘V) dans l'app, jamais lu par le lanceur de tests : une lecture directe du contenu
/// d'une autre app peut déclencher l'alerte d'accès au presse-papiers de macOS.
final class CopyURLUITests: XCTestCase {
    private static let address = "about:blank?copy"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Confirmation affichée, avec son texte français.
    @MainActor
    private func confirmation(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label == %@", "copyConfirmation", "URL copiée"))
            .firstMatch
    }

    /// Lance l'app et attend sa fenêtre (aucun onglet).
    @MainActor
    private func launch() -> XCUIApplication {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        return app
    }

    /// Remplace le contenu du presse-papiers par `text` : écrire ne déclenche aucune alerte.
    private func writePasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Ouvre `about:blank?copy` par la barre de commande, puis remplace le presse-papiers.
    @MainActor
    private func openPage(in app: XCUIApplication) {
        openAddress(Self.address, in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == Self.address })
        writePasteboard("avant")
    }

    /// Colle (⌘V) dans la barre de commande (⌘T), puis la referme : un collage voulu, sans alerte
    /// d'accès au presse-papiers. Vrai si le champ reçoit `expected`.
    @MainActor
    private func pastes(_ expected: String, in app: XCUIApplication) -> Bool {
        let field = openCommandBar(in: app)
        app.typeKey("v", modifierFlags: .command)
        let pasted = waitForValue(of: field, timeout: 3) { $0 == expected }
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        return pasted
    }

    /// Juste après la copie : la confirmation apparaît puis disparaît seule ; l'adresse est copiée.
    @MainActor
    private func assertCopied(in app: XCUIApplication) {
        let confirmation = confirmation(in: app)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
        XCTAssertTrue(pastes(Self.address, in: app))
    }

    /// Élément « Copier l'URL » du menu Édition devenu (in)actif.
    @MainActor
    private func waitForMenuItem(_ item: XCUIElement, enabled: Bool) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == %@", NSNumber(value: enabled))
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: item)], timeout: 3) == .completed
    }

    @MainActor
    func testShiftCommandCCopiesTheURL() {
        let app = launch()
        // Sans onglet, la commande est grisée : ⇧⌘C ne copie ni ne confirme rien.
        let menuItem = app.menuBars.menuItems["Copier l'URL"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 2))
        XCTAssertTrue(waitForMenuItem(menuItem, enabled: false))
        writePasteboard("avant")
        app.typeKey("c", modifierFlags: [.command, .shift])
        XCTAssertFalse(confirmation(in: app).waitForExistence(timeout: 1))
        // ⌘T puis Échap ne laisse aucun onglet.
        XCTAssertTrue(pastes("avant", in: app))
        XCTAssertTrue(waitForCount(tabRows(in: app), 0))

        openPage(in: app)
        XCTAssertTrue(waitForMenuItem(menuItem, enabled: true))
        app.typeKey("c", modifierFlags: [.command, .shift])
        assertCopied(in: app)
    }

    @MainActor
    func testCommandBarActionCopiesTheURL() {
        let app = launch()
        openPage(in: app)
        let field = openCommandBar(in: app, newTab: false)
        let row = commandBarRows(in: app).matching(NSPredicate(format: "label == %@", "Copier l'URL")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        // Même confirmation que ⇧⌘C ; la barre s'est fermée.
        assertCopied(in: app)
        XCTAssertFalse(field.exists)
    }

    @MainActor
    func testContextMenuCopyLinkShowsTheConfirmation() {
        let app = launch()
        openPage(in: app)
        tabRow(titled: Self.address, in: app).rightClick()
        app.menuItems["Copier le lien"].click()
        assertCopied(in: app)
    }
}
