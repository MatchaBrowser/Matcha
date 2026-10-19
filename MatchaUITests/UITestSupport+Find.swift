import XCTest

/// Find in page (task 5.3): bar, field and result.
extension XCTestCase {
    /// Field of the find bar; its value is the searched text.
    @MainActor
    func findField(in app: XCUIApplication) -> XCUIElement {
        app.textFields["findField"].firstMatch
    }

    /// “Not Found”, shown at the end of the field when the last search found nothing.
    @MainActor
    func findStatus(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "findStatus").firstMatch
    }

    /// Button of the bar: `findPreviousButton`, `findNextButton`, `findCloseButton`.
    @MainActor
    func findButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons[identifier].firstMatch
    }

    /// ⌘F: the bar opens (or stays open) and its field takes keyboard focus.
    @MainActor
    @discardableResult
    func openFindBar(in app: XCUIApplication) -> XCUIElement {
        app.typeKey("f", modifierFlags: .command)
        let field = findField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        return field
    }

    /// The field has keyboard focus: ⌘A then `text`, which replaces the searched text.
    @MainActor
    func replaceFindText(with text: String, in app: XCUIApplication) {
        app.typeKey("a", modifierFlags: .command)
        app.typeText(text)
    }

    /// “Not Found” is shown (text or value of the element, depending on what SwiftUI exposes).
    @MainActor
    func waitForNotFound(in app: XCUIApplication, timeout: TimeInterval = 3) -> Bool {
        let status = findStatus(in: app)
        guard status.waitForExistence(timeout: timeout) else {
            return false
        }
        return status.label == "Introuvable" || status.value as? String == "Introuvable"
    }
}
