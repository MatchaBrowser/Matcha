import AppKit
import XCTest

/// Icon of a Space: grid of symbols and emoji in the Space editor (click on the icon of the displayed Space, or
/// “Change Icon…” in its menu). In Debug, the accessibility value of a Space's button is its icon in its stored
/// form (“symbol:star.fill”, “emoji:🌿”).
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
        // Names translated for VoiceOver and the tooltips.
        XCTAssertEqual(app.buttons["spaceSymbol.star.fill"].label, "Étoile")
        XCTAssertEqual(app.buttons["spaceSymbol.mountain.2.fill"].label, "Montagnes")

        clickWhenSettled(app.buttons["spaceSymbol.mountain.2.fill"])
        XCTAssertTrue(waitForValue(of: space, timeout: 3) { $0 == "symbol:mountain.2.fill" })
        XCTAssertTrue(app.buttons["spaceSymbol.mountain.2.fill"].isSelected)
        XCTAssertFalse(app.buttons["spaceSymbol.circle.fill"].isSelected)

        // An emoji pasted into the field replaces the symbol, which is no longer circled.
        let field = app.textFields["spaceEmojiField"]
        field.click()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("🌿", forType: .string)
        field.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(waitForValue(of: space, timeout: 3) { $0 == "emoji:🌿" })
        XCTAssertFalse(app.buttons["spaceSymbol.mountain.2.fill"].isSelected)
        // A letter is rejected: the field goes back to the emoji.
        field.typeText("a")
        XCTAssertTrue(waitForValue(of: field, timeout: 3) { $0 == "🌿" })
        XCTAssertEqual(space.value as? String, "emoji:🌿")
        // Field cleared: the circle, the default icon.
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(waitForValue(of: space, timeout: 3) { $0 == "symbol:circle.fill" })
        XCTAssertTrue(app.buttons["spaceSymbol.circle.fill"].isSelected)

        // Escape in the field closes the popover; the icon stays.
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(editor.waitForNonExistence(timeout: 3))
        XCTAssertEqual(space.value as? String, "symbol:circle.fill")
    }

    @MainActor
    func testContextMenuOpensTheEditorOfThatSpace() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        createSpace(in: app)
        XCTAssertTrue(waitForCount(spaceButtons(in: app), 2))
        let first = spaceButtons(in: app).element(boundBy: 0)
        let second = spaceButtons(in: app).element(boundBy: 1)
        XCTAssertEqual(second.value as? String, "symbol:star.fill")

        // Menu of the first Space, which is no longer displayed: no more symbols submenu.
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

        // A click beside it closes the popover.
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
