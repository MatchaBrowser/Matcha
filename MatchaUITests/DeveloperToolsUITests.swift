import XCTest

/// Web developer tools (Settings > Advanced): “Inspect Element” in the page menu opens the web inspector in Matcha;
/// with the setting off, the item goes away. Local page without network (Postfix documentation).
final class DeveloperToolsUITests: XCTestCase {
    private let page = "file:///usr/share/doc/postfix/html/index.html"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: "/usr/share/doc/postfix/html/index.html"),
            "Documentation de Postfix absente",
        )
    }

    /// Opens the page, then the context menu on its title; returns the “Inspect Element” item (possibly missing).
    @MainActor
    private func inspectItem(settings: [String: String]) -> (XCUIApplication, XCUIElement) {
        let app = launchApp(settings: settings)
        XCTAssertTrue(waitForBrowserWindow(of: app))
        app.typeKey("t", modifierFlags: .command)
        app.typeText("\(page)\n")
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5))
        XCTAssertTrue(webView.staticTexts["Postfix Documentation"].waitForExistence(timeout: 5))
        webView.staticTexts["Postfix Documentation"].rightClick()
        return (app, app.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Inspecter'")).firstMatch)
    }

    @MainActor
    func testInspectElementOpensTheWebInspectorInMatcha() {
        let (app, item) = inspectItem(settings: ["showsDeveloperTools": "YES"])
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        let page = app.descendants(matching: .any)["pagePane"].scrollViews.firstMatch
        let height = page.frame.height
        item.click()
        // The inspector opens below the page, in the card: the page shrinks (its content isn't exposed to
        // accessibility).
        let shrunk = NSPredicate { _, _ in page.frame.height < height - 100 }
        wait(for: [XCTNSPredicateExpectation(predicate: shrunk, object: nil)], timeout: 5)
    }

    @MainActor
    func testWithoutTheSettingThereIsNoInspector() {
        let (app, item) = inspectItem(settings: ["showsDeveloperTools": "NO"])
        XCTAssertTrue(app.menuItems.firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(item.exists)
        app.typeKey(.escape, modifierFlags: [])
    }
}
