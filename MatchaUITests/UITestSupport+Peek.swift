import Foundation
import XCTest

/// Outils des tests de l'aperçu (Peek, tâche 4.4). Pages : la documentation de Postfix livrée avec macOS, sans
/// réseau. « Basic configuration » (sur `index.html`) mène à `BASIC_CONFIGURATION_README.html`, dont les liens
/// « main.cf » mènent à `postconf.5.html`. `index.html` n'a qu'un lien « All main.cf parameters ».
extension XCTestCase {
    static let localDocsPath = "/usr/share/doc/postfix/html/index.html"

    /// Ouvre la documentation de Postfix dans un nouvel onglet ; le test est ignoré si elle manque.
    @MainActor
    func openLocalDocs(in app: XCUIApplication) throws {
        try XCTSkipUnless(FileManager.default.isReadableFile(atPath: Self.localDocsPath), "Documentation de Postfix absente")
        openAddress("file://" + Self.localDocsPath, in: app)
        XCTAssertTrue(tabRow(titled: "Postfix Documentation", in: app).waitForExistence(timeout: 10))
    }

    /// Liens de la page dont le texte contient `text` (ou vaut `text` si `exact`). Si l'accessibilité des pages
    /// n'expose pas les liens, repli sur les textes, signalé dans le rapport du test.
    @MainActor
    func links(_ text: String, exact: Bool = false, in app: XCUIApplication) -> XCUIElementQuery {
        let comparison = exact ? "==" : "CONTAINS"
        // Le texte d'un lien de page est son titre (son libellé est souvent vide) ; sa valeur est son adresse.
        let links = app.links.matching(NSPredicate(format: "title \(comparison) %@ OR label \(comparison) %@", text, text))
        if links.firstMatch.waitForExistence(timeout: 10) {
            return links
        }
        XCTContext.runActivity(named: "Aucun lien « \(text) » exposé : repli sur les textes de la page") { _ in }
        return app.staticTexts.matching(NSPredicate(format: "label \(comparison) %@ OR value \(comparison) %@", text, text))
    }

    /// Premier lien dont le texte contient `text`.
    @MainActor
    func link(containing text: String, in app: XCUIApplication) -> XCUIElement {
        links(text, in: app).firstMatch
    }

    /// Maj+clic, comme l'utilisateur (la vraie touche est tenue pendant le clic).
    @MainActor
    func shiftClick(_ element: XCUIElement) {
        XCUIElement.perform(withKeyModifiers: .shift) {
            element.click()
        }
    }

    /// Élément de l'aperçu : `peek` (la couche), `peekAddress`, `peekOpenAsTabButton`, `peekCloseButton`.
    @MainActor
    func peekElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Maj+clic sur « Basic configuration » de la page affichée : l'aperçu s'ouvre sur cette page.
    @MainActor
    func openPeekOnLocalDocs(in app: XCUIApplication) {
        let source = link(containing: "Basic configuration", in: app)
        XCTAssertTrue(source.exists)
        shiftClick(source)
        XCTAssertTrue(peekElement("peekCloseButton", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: peekElement("peekAddress", in: app), timeout: 10) { $0 == "BASIC_CONFIGURATION_README.html" })
    }

    /// Attend que la valeur de `element` soit vide (pastille d'un onglet sans adresse).
    @MainActor
    func waitForEmptyValue(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate { object, _ in
            ((object as? XCUIElement)?.value as? String ?? "").isEmpty
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }
}
