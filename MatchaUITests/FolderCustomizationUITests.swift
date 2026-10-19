import XCTest

/// Customization of a pinned folder: panel opened below its row by “Customize…”, symbol, text and background
/// colors, “Reset”, closing with the cross, the menu or Escape. In Debug, the row's accessibility value sums up
/// its appearance (“symbol:star text:#FF3B30 background:#FFCC00”).
final class FolderCustomizationUITests: XCTestCase {
    private static let defaultAppearance = "default text:none background:none"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCustomizeResetAndClose() {
        let app = launchApp()
        let folder = makeFolder(named: "Projets", in: app)
        XCTAssertEqual(folder.value as? String, Self.defaultAppearance)
        // Nothing opens by itself.
        let panel = customizationPanel(in: app)
        XCTAssertFalse(panel.exists)

        openCustomization(of: folder, in: app)
        // Below the folder row (once the animation is over), with its name.
        sleep(1)
        XCTAssertGreaterThanOrEqual(panel.frame.minY, folder.frame.maxY - 1)
        XCTAssertEqual(panel.staticTexts["folderCustomizationTitle"].value as? String, "Projets")
        XCTAssertTrue(app.buttons["folderSymbol.folder"].isSelected)
        XCTAssertTrue(app.buttons["folderTextColor.none"].isSelected)
        XCTAssertFalse(app.buttons["folderAppearanceResetButton"].isEnabled)
        // Names translated for VoiceOver.
        XCTAssertEqual(app.buttons["folderSymbol.star"].label, "Étoile")
        XCTAssertEqual(app.buttons["folderBackgroundColor.yellow"].label, "Jaune")

        clickWhenSettled(app.buttons["folderSymbol.star"])
        XCTAssertTrue(waitForValue(of: folder, timeout: 3) { $0 == "symbol:star text:none background:none" })
        XCTAssertTrue(app.buttons["folderSymbol.star"].isSelected)
        XCTAssertFalse(app.buttons["folderSymbol.folder"].isSelected)

        app.buttons["folderTextColor.red"].click()
        app.buttons["folderBackgroundColor.yellow"].click()
        XCTAssertTrue(waitForValue(of: folder, timeout: 3) { $0 == "symbol:star text:#FF3B30 background:#FFCC00" })
        XCTAssertTrue(app.buttons["folderTextColor.red"].isSelected)
        XCTAssertTrue(app.buttons["folderBackgroundColor.yellow"].isSelected)
        XCTAssertFalse(app.buttons["folderBackgroundColor.none"].isSelected)

        // “No Color” for the text: the app picks a color that reads well on the background.
        app.buttons["folderTextColor.none"].click()
        XCTAssertTrue(waitForValue(of: folder, timeout: 3) { $0 == "symbol:star text:none background:#FFCC00" })

        app.buttons["folderAppearanceResetButton"].click()
        XCTAssertTrue(waitForValue(of: folder, timeout: 3) { $0 == Self.defaultAppearance })
        XCTAssertTrue(app.buttons["folderSymbol.folder"].isSelected)

        app.buttons["folderCustomizationCloseButton"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
        // The chosen appearance stays when the panel closes.
        XCTAssertEqual(folder.value as? String, Self.defaultAppearance)
    }

    @MainActor
    func testMenuAndEscapeClose() {
        let app = launchApp()
        let folder = makeFolder(named: "Lectures", in: app)
        let panel = customizationPanel(in: app)

        openCustomization(of: folder, in: app)
        clickWhenSettled(app.buttons["folderSymbol.book"])
        XCTAssertTrue(waitForValue(of: folder, timeout: 3) { $0.hasPrefix("symbol:book ") })
        // With the panel open, the folder's menu offers to close it.
        folder.rightClick()
        app.menuItems["Fermer la personnalisation"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
        XCTAssertEqual(folder.value as? String, "symbol:book text:none background:none")

        // Escape closes the panel, which takes keyboard focus when it opens.
        openCustomization(of: folder, in: app)
        sleep(1)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
    }

    /// Empty pinned tab, then a folder created from it and named `name`.
    @MainActor
    private func makeFolder(named name: String, in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Épingler"].click()
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Nouveau dossier"].click()
        let field = app.textFields["folderNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        app.typeText("\(name)\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        let folder = folderRow(in: app)
        XCTAssertEqual(folder.label, name)
        return folder
    }

    @MainActor
    private func openCustomization(of folder: XCUIElement, in app: XCUIApplication) {
        folder.rightClick()
        app.menuItems["Personnaliser…"].click()
        XCTAssertTrue(customizationPanel(in: app).waitForExistence(timeout: 3))
    }
}

extension XCTestCase {
    /// First folder row of the sidebar.
    @MainActor
    func folderRow(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "folderRow").firstMatch
    }

    /// Customization panel of a folder.
    @MainActor
    func customizationPanel(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "folderCustomizationPanel").firstMatch
    }
}
