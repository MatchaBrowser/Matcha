import AppKit
import XCTest

/// Copy URL (⇧⌘C, command bar action, context menu): the address reaches the pasteboard and the “URL Copied”
/// confirmation appears then goes away by itself. Offline: `about:blank?copy`. These tests write to the general
/// pasteboard; its content is checked by pasting (⌘V) in the app, never read by the test runner: directly reading
/// the content of another app can trigger the macOS pasteboard access alert.
final class CopyURLUITests: XCTestCase {
    private static let address = "about:blank?copy"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Confirmation shown, with its French text.
    @MainActor
    private func confirmation(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label == %@", "copyConfirmation", "URL copiée"))
            .firstMatch
    }

    /// Launches the app and waits for its window (no tab).
    @MainActor
    private func launch() -> XCUIApplication {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        return app
    }

    /// Replaces the pasteboard content with `text`: writing triggers no alert.
    private func writePasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Opens `about:blank?copy` from the command bar, then replaces the pasteboard.
    @MainActor
    private func openPage(in app: XCUIApplication) {
        openAddress(Self.address, in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == Self.address })
        writePasteboard("avant")
    }

    /// Pastes (⌘V) into the command bar (⌘T), then closes it: an intentional paste, without a pasteboard access
    /// alert. True if the field receives `expected`.
    @MainActor
    private func pastes(_ expected: String, in app: XCUIApplication) -> Bool {
        let field = openCommandBar(in: app)
        app.typeKey("v", modifierFlags: .command)
        let pasted = waitForValue(of: field, timeout: 3) { $0 == expected }
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        return pasted
    }

    /// Right after the copy: the confirmation appears then goes away by itself; the address is copied.
    @MainActor
    private func assertCopied(in app: XCUIApplication) {
        let confirmation = confirmation(in: app)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
        XCTAssertTrue(pastes(Self.address, in: app))
    }

    /// “Copy URL” item of the Edit menu, once it becomes enabled (or disabled).
    @MainActor
    private func waitForMenuItem(_ item: XCUIElement, enabled: Bool) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == %@", NSNumber(value: enabled))
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: item)], timeout: 3) == .completed
    }

    @MainActor
    func testShiftCommandCCopiesTheURL() {
        let app = launch()
        // Without a tab, the command is grayed out: ⇧⌘C neither copies nor confirms anything.
        let menuItem = app.menuBars.menuItems["Copier l'URL"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 2))
        XCTAssertTrue(waitForMenuItem(menuItem, enabled: false))
        writePasteboard("avant")
        app.typeKey("c", modifierFlags: [.command, .shift])
        XCTAssertFalse(confirmation(in: app).waitForExistence(timeout: 1))
        // ⌘T then Escape leaves no tab.
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
        // Same confirmation as ⇧⌘C; the bar has closed.
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
