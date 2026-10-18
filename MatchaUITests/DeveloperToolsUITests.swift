import XCTest

/// Outils pour développeurs web (Réglages > Avancé) : « Inspecter l'élément » dans le menu des pages ouvre l'inspecteur
/// web dans Matcha ; réglage désactivé, l'élément disparaît. Page locale sans réseau (documentation de Postfix).
final class DeveloperToolsUITests: XCTestCase {
    private let page = "file:///usr/share/doc/postfix/html/index.html"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: "/usr/share/doc/postfix/html/index.html"),
            "Documentation de Postfix absente",
        )
    }

    /// Ouvre la page, puis le menu contextuel sur son titre ; renvoie l'élément « Inspecter l'élément » (peut-être absent).
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
        // L'inspecteur s'ouvre sous la page, dans la carte : la page rétrécit (son contenu n'est pas exposé à
        // l'accessibilité).
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
