import XCTest

/// Settings: window, search engine, alert before quitting.
final class SettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSettingsWindowOpensAndClosesWithCommandW() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        app.typeKey(",", modifierFlags: .command)
        // The window reopens on the last viewed tab.
        let generalTab = app.toolbars.buttons["Général"]
        XCTAssertTrue(generalTab.waitForExistence(timeout: 5))
        generalTab.click()
        let picker = app.descendants(matching: .any).matching(identifier: "searchEnginePicker").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 2)
        // Peek for links in Favorites and pinned tabs: off by default (only read, never changed here).
        let peekToggle = app.descendants(matching: .any).matching(identifier: "pinnedLinksInPeekToggle").firstMatch
        XCTAssertTrue(peekToggle.exists)
        // Checkbox or switch: value 0 (number or text depending on the control).
        XCTAssertEqual(peekToggle.value.map { "\($0)" }, "0")
        // Memory of inactive tabs (task 5.6): the choice is there (only read, never changed here).
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "tabSuspensionDelayPicker").firstMatch.exists)

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(picker.waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.windows.count, 1)
    }

    /// Settings > Extensions (task 6.4): with a test store, none of the user's extensions is visible; the Safari
    /// extensions section and “Choose…” are there. Nothing is installed here.
    @MainActor
    func testExtensionsTabListsNothingOfTheUser() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        app.typeKey(",", modifierFlags: .command)
        let extensionsTab = app.toolbars.buttons["Extensions"]
        XCTAssertTrue(extensionsTab.waitForExistence(timeout: 5))
        extensionsTab.click()
        let emptyState = app.descendants(matching: .any).matching(identifier: "extensionsEmptyState").firstMatch
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "extensionsChooseFileButton").firstMatch.exists)
        // Links to the stores (never clicked here: the App Store would open).
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "extensionsAppStoreButton").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "extensionsFirefoxAddOnsButton").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "installedExtensionRow").firstMatch.exists)
        app.typeKey("w", modifierFlags: .command)
    }

    /// Mini window shortcut shown in General (⌃⌥⇧⌘N given at launch: never ⌥⌘N, which would reach the user's
    /// Matcha). The field is never clicked: no shortcut is recorded by a test.
    @MainActor
    func testMiniWindowShortcutIsShownInGeneralSettings() {
        let app = launchApp(settings: ["KeyboardShortcuts_openMiniWindow": Self.shortcutArgument(keyCode: 45, carbonModifiers: 6912)])
        XCTAssertTrue(waitForBrowserWindow(of: app))
        app.typeKey(",", modifierFlags: .command)
        let generalTab = app.toolbars.buttons["Général"]
        XCTAssertTrue(generalTab.waitForExistence(timeout: 5))
        generalTab.click()
        let label = "Raccourci de la mini-fenêtre"
        let title = app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", label, label)).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        // The recorder field is a search field; its symbols come in the order ⌃ ⌥ ⇧ ⌘.
        let recorder = app.searchFields.firstMatch
        XCTAssertTrue(recorder.waitForExistence(timeout: 3))
        XCTAssertTrue((recorder.value as? String)?.hasPrefix("⌃⌥⇧⌘") == true, "\(String(describing: recorder.value))")
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

        // Without a tab, Home opens one.
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
        // The command bar opens on the created tab and shows its full URL.
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
