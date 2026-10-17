import XCTest

/// Réglages : fenêtre, moteur de recherche, alerte avant de quitter.
final class SettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSettingsWindowOpensAndClosesWithCommandW() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        app.typeKey(",", modifierFlags: .command)
        // La fenêtre rouvre le dernier onglet consulté.
        let generalTab = app.toolbars.buttons["Général"]
        XCTAssertTrue(generalTab.waitForExistence(timeout: 5))
        generalTab.click()
        let picker = app.descendants(matching: .any).matching(identifier: "searchEnginePicker").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 2)

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(picker.waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.windows.count, 1)
    }

    @MainActor
    func testSearchUsesTheChosenEngine() throws {
        try skipIfOffline()
        let app = launchApp(settings: ["searchEngine": "duckDuckGo"])
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openAddress("pain au levain", in: app)
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "duckduckgo.com" })
    }

    @MainActor
    func testQuittingAsksForConfirmation() {
        let app = launchApp(settings: ["confirmBeforeQuitting": "YES"])
        XCTAssertTrue(waitForBrowserWindow(of: app))
        app.typeKey("q", modifierFlags: .command)
        let cancel = app.buttons["Annuler"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Quitter Matcha ?"].exists)
        cancel.click()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testHomeButtonAndShortcutOpenTheHomePage() {
        let app = launchApp(settings: ["showsHomeButton": "YES", "homePage": "about:blank"])
        XCTAssertTrue(waitForBrowserWindow(of: app))
        let home = app.buttons["homeButton"]
        XCTAssertTrue(home.exists)
        let pill = addressPill(in: app)

        // Sans onglet, Accueil en ouvre un.
        home.click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(waitForValue(of: pill) { $0 == "about:blank" })

        openEmptyTab(in: app)
        app.typeKey("h", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(of: pill) { $0 == "about:blank" })
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
    }

    @MainActor
    func testHomeButtonIsHiddenWhenTurnedOffOrWithoutHomePage() {
        for settings in [["showsHomeButton": "NO", "homePage": "apple.com"], ["showsHomeButton": "YES", "homePage": ""]] {
            let app = launchApp(settings: settings)
            XCTAssertTrue(waitForBrowserWindow(of: app))
            XCTAssertFalse(app.buttons["homeButton"].exists, "\(settings)")
            app.terminate()
        }
    }

    @MainActor
    func testNewTabsCanOpenTheHomePage() {
        let app = launchApp(settings: ["newTabPage": "homePage", "homePage": "about:blank"])
        let field = addressField(in: app)
        XCTAssertTrue(waitForBrowserWindow(of: app))
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        // La barre de commande s'ouvre sur l'onglet créé et montre son URL complète.
        XCTAssertTrue(waitForValue(of: field) { $0 == "about:blank" })
    }

    @MainActor
    func testHomeButtonSettingExplainsWhenNoHomePageIsSet() {
        for (homePage, showsHint) in [("", true), ("apple.com", false)] {
            let app = launchApp(settings: ["homePage": homePage])
            XCTAssertTrue(waitForBrowserWindow(of: app))
            app.typeKey(",", modifierFlags: .command)
            let appearanceTab = app.toolbars.buttons["Apparence"]
            XCTAssertTrue(appearanceTab.waitForExistence(timeout: 5))
            appearanceTab.click()
            let hintText = "page d'accueil choisie"
            let predicate = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", hintText, hintText)
            let hint = app.staticTexts.matching(predicate).firstMatch
            XCTAssertEqual(hint.waitForExistence(timeout: 2), showsHint, "page d'accueil « \(homePage) »")
            app.terminate()
        }
    }
}
