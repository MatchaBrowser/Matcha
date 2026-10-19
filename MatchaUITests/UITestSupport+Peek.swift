import Foundation
import XCTest

/// Helpers for the Peek tests (task 4.4). Pages: the Postfix documentation shipped with macOS, without
/// network. “Basic configuration” (on `index.html`) leads to `BASIC_CONFIGURATION_README.html`, whose
/// “main.cf” links lead to `postconf.5.html`. `index.html` has only one “All main.cf parameters” link.
extension XCTestCase {
    static let localDocsPath = "/usr/share/doc/postfix/html/index.html"

    /// Opens the Postfix documentation in a new tab; the test is skipped if it is missing.
    @MainActor
    func openLocalDocs(in app: XCUIApplication) throws {
        try XCTSkipUnless(FileManager.default.isReadableFile(atPath: Self.localDocsPath), "Documentation de Postfix absente")
        openAddress("file://" + Self.localDocsPath, in: app)
        XCTAssertTrue(tabRow(titled: "Postfix Documentation", in: app).waitForExistence(timeout: 10))
    }

    /// Links of the page whose text contains `text` (or equals `text` if `exact`). If page accessibility doesn't
    /// expose the links, falls back to the texts, flagged in the test report.
    @MainActor
    func links(_ text: String, exact: Bool = false, in app: XCUIApplication) -> XCUIElementQuery {
        let comparison = exact ? "==" : "CONTAINS"
        // The text of a page link is its title (its label is often empty); its value is its address.
        let links = app.links.matching(NSPredicate(format: "title \(comparison) %@ OR label \(comparison) %@", text, text))
        if links.firstMatch.waitForExistence(timeout: 10) {
            return links
        }
        XCTContext.runActivity(named: "Aucun lien « \(text) » exposé : repli sur les textes de la page") { _ in }
        return app.staticTexts.matching(NSPredicate(format: "label \(comparison) %@ OR value \(comparison) %@", text, text))
    }

    /// First link whose text contains `text`.
    @MainActor
    func link(containing text: String, in app: XCUIApplication) -> XCUIElement {
        links(text, in: app).firstMatch
    }

    /// Shift-click, like the user (the real key is held down during the click).
    @MainActor
    func shiftClick(_ element: XCUIElement) {
        XCUIElement.perform(withKeyModifiers: .shift) {
            element.click()
        }
    }

    /// Peek element: `peek` (the layer), `peekAddress`, `peekOpenAsTabButton`, `peekCloseButton`.
    @MainActor
    func peekElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Shift-click on “Basic configuration” of the displayed page: Peek opens on that page.
    @MainActor
    func openPeekOnLocalDocs(in app: XCUIApplication) {
        let source = link(containing: "Basic configuration", in: app)
        XCTAssertTrue(source.exists)
        shiftClick(source)
        XCTAssertTrue(peekElement("peekCloseButton", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: peekElement("peekAddress", in: app), timeout: 10) { $0 == "BASIC_CONFIGURATION_README.html" })
    }

    /// Waits for the value of `element` to be empty (pill of a tab without an address).
    @MainActor
    func waitForEmptyValue(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate { object, _ in
            ((object as? XCUIElement)?.value as? String ?? "").isEmpty
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }
}
