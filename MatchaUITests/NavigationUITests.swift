import XCTest

/// Navigation et raccourcis : on pilote l'app comme un utilisateur.
final class NavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStartsWithoutTabsOrCommandBar() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        XCTAssertEqual(tabRows(in: app).count, 0)
        // La barre ne s'ouvre jamais d'elle-même : la page vide invite à ⌘T.
        let hint = "Appuyez sur ⌘T"
        let predicate = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", hint, hint)
        XCTAssertTrue(app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(addressField(in: app).waitForExistence(timeout: 1))
    }

    @MainActor
    func testAddressFieldLoadsPage() throws {
        try skipIfOffline()
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openAddress("example.com", in: app)

        XCTAssertTrue(tabRow(titled: "Example Domain", in: app).waitForExistence(timeout: 20))
        XCTAssertEqual(tabRows(in: app).count, 1)
        // La pastille n'affiche que le domaine.
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "example.com" })
    }

    // MARK: Raccourcis

    @MainActor
    func testCommandTOpensTheCommandBarWithoutCreatingATab() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))

        // ⌘T ouvre la barre sans créer d'onglet ; Échap ne laisse rien.
        let field = openCommandBar(in: app)
        XCTAssertEqual(tabRows(in: app).count, 0)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 0)

        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
    }

    @MainActor
    func testCommandWClosesTabsButNotTheWindow() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))

        app.typeKey("w", modifierFlags: .command)
        XCTAssertEqual(tabRows(in: app).count, 1)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertEqual(tabRows(in: app).count, 0)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertEqual(app.windows.count, 1)
    }

    @MainActor
    func testCommandShiftWClosesTheWindow() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.windows.firstMatch.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testCommandLFocusesAddressField() {
        let app = launchApp()
        let field = addressField(in: app)
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        tabRows(in: app).firstMatch.click()
        XCTAssertFalse(field.exists)

        // Onglet vide : la barre s'ouvre sur un texte vide.
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        XCTAssertEqual(field.value as? String, "")
    }

    @MainActor
    func testHistoryShortcutsGoBackAndForward() throws {
        try skipIfOffline()
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openAddress("example.com", in: app)
        XCTAssertTrue(tabRow(titled: "Example Domain", in: app).waitForExistence(timeout: 20))

        openAddress("example.org", in: app, newTab: false)
        let pill = addressPill(in: app)
        XCTAssertTrue(waitForValue(of: pill) { $0 == "example.org" })

        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(waitForValue(of: pill) { $0 == "example.com" })
        app.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(waitForValue(of: pill) { $0 == "example.org" })
        XCTAssertEqual(tabRows(in: app).count, 1)
    }

    @MainActor
    func testCommandWKeepsPinnedTabs() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Épingler"].click()
        tabRows(in: app).firstMatch.click()

        // L'épinglé reste ; la sélection passe à l'onglet du jour, que ⌘W ferme pour de bon.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
    }
}
