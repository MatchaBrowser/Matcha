import XCTest

/// History window (task 5.5): ⌘Y, rows, search, clearing.
extension XCTestCase {
    /// “History” window.
    @MainActor
    func historyWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows.matching(NSPredicate(format: "title == %@", "Historique")).firstMatch
    }

    /// ⌘Y: the history window opens (or comes to the front).
    @MainActor
    @discardableResult
    func openHistoryWindow(in app: XCUIApplication) -> XCUIElement {
        app.typeKey("y", modifierFlags: .command)
        let window = historyWindow(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        return window
    }

    /// History rows; their label is the page title, their value its domain.
    @MainActor
    func historyRows(in scope: XCUIElement) -> XCUIElementQuery {
        scope.descendants(matching: .any).matching(identifier: "historyRow")
    }

    /// History row whose title is exactly `title`.
    @MainActor
    func historyRow(titled title: String, in scope: XCUIElement) -> XCUIElement {
        historyRows(in: scope).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// “No History” text of the empty window.
    @MainActor
    func historyEmptyState(in scope: XCUIElement) -> XCUIElement {
        scope.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", "Aucun historique", "Aucun historique")).firstMatch
    }

    /// Button of an alert or a sheet of the app (the clearing dialog can be either). Query resolved at each use:
    /// the button may be requested before the dialog appears.
    @MainActor
    func dialogButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let dialogs = app.descendants(matching: .any).matching(NSPredicate(
            format: "elementType == %lu OR elementType == %lu",
            XCUIElement.ElementType.sheet.rawValue,
            XCUIElement.ElementType.dialog.rawValue,
        ))
        return dialogs.buttons[title].firstMatch
    }

    /// Postfix documentation opened (no network), then its “Basic configuration” page in the same tab:
    /// two visits, “Postfix Documentation” and “Postfix Basic Configuration”.
    @MainActor
    func visitLocalDocs(in app: XCUIApplication) throws {
        try openLocalDocs(in: app)
        clickWhenSettled(link(containing: "Basic configuration", in: app))
        XCTAssertTrue(waitForValue(of: addressPill(in: app), timeout: 10) { $0 == "BASIC_CONFIGURATION_README.html" })
        XCTAssertTrue(tabRow(titled: "Postfix Basic Configuration", in: app).waitForExistence(timeout: 10))
    }
}
