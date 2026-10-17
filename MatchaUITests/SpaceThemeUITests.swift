import XCTest

/// Éditeur du thème du Space.
final class SpaceThemeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testThemeEditorOffersPresetsAndCloses() {
        let app = launchApp()
        let spaceButton = app.buttons["spaceButton"]
        XCTAssertTrue(spaceButton.waitForExistence(timeout: 5))
        spaceButton.click()

        let presets = app.descendants(matching: .any).matching(identifier: "themePreset")
        XCTAssertTrue(presets.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(presets.count, 6)
        app.buttons["Forêt"].click()
        XCTAssertTrue(app.sliders.firstMatch.exists)

        // Un clic à côté ferme le popover.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).click()
        XCTAssertTrue(presets.firstMatch.waitForNonExistence(timeout: 3))
    }
}
