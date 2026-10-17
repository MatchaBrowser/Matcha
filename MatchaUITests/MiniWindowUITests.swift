import XCTest

/// Mini-fenêtre (équivalent de Little Arc). Ouverte par le menu Fichier : le raccourci global est coupé par les
/// réglages de lancement (`defaultSettings`), sauf dans le test qui le vérifie, qui en choisit un que personne
/// n'utilise (⌃⌥⌘F18). Ces tests activent le Finder et utilisent la vraie souris.
final class MiniWindowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMenuOpensAMiniWindowThatLoadsTypedAddresses() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        let mini = openMiniWindow(in: app)
        load("about:blank?one", in: mini, app: app)

        // La page reste dans la mini-fenêtre : aucun onglet dans la barre latérale.
        XCTAssertEqual(tabRows(in: app).count, 0)
        XCTAssertFalse(addressField(in: browserWindow(in: app)).exists)
    }

    @MainActor
    func testEscapeOnAnEmptyMiniWindowClosesIt() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openMiniWindow(in: app)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForCount(miniWindows(in: app), 0))
    }

    @MainActor
    func testCommandLEditsTheMiniWindowAddressAndBackAppears() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        let mini = openMiniWindow(in: app)
        load("about:blank?one", in: mini, app: app)
        XCTAssertFalse(mini.buttons["Précédent"].exists)

        app.typeKey("l", modifierFlags: .command)
        let field = addressField(in: mini)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        XCTAssertEqual(field.value as? String, "about:blank?one")
        load("about:blank?two", in: mini, app: app)
        XCTAssertTrue(mini.buttons["Précédent"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCommandWClosesOnlyTheMiniWindow() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openAddress("about:blank?main", in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        let mini = openMiniWindow(in: app)
        load("about:blank?mini", in: mini, app: app)

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(miniWindows(in: app), 0))
        XCTAssertEqual(tabRows(in: app).count, 1)
    }

    @MainActor
    func testMiniWindowStaysAboveTheBrowserWindow() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        let mini = openMiniWindow(in: app)
        load("about:blank?mini", in: mini, app: app)

        uncoveredPoint(of: browserWindow(in: app), avoiding: mini).click()
        // Fenêtre de navigation active : la mini-fenêtre reste devant elle.
        XCTAssertTrue(addressPill(in: mini).isHittable)
    }

    @MainActor
    func testOpenInSpaceMovesTheLivePageIntoTheSidebar() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        let mini = openMiniWindow(in: app)
        load("about:blank?one", in: mini, app: app)
        app.typeKey("l", modifierFlags: .command)
        load("about:blank?two", in: mini, app: app)

        let open = openInSpaceButton(in: mini)
        XCTAssertEqual(open.value as? String, "Perso")
        open.click()
        XCTAssertTrue(waitForCount(miniWindows(in: app), 0))
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(tabRow(titled: "about:blank?two", in: app).exists)
        // Même vue web : l'historique a suivi (un onglet recréé depuis l'adresse n'en aurait pas).
        XCTAssertTrue(app.buttons["Précédent"].isEnabled)
    }

    @MainActor
    func testCommandOReopensTheClosedBrowserWindowWithThePage() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["newTabButton"].waitForNonExistence(timeout: 5))
        let mini = openMiniWindow(in: app)
        load("about:blank?one", in: mini, app: app)

        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(waitForBrowserWindow(of: app))
        XCTAssertTrue(waitForCount(miniWindows(in: app), 0))
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(waitForValue(of: addressPill(in: browserWindow(in: app))) { $0 == "about:blank?one" })
    }

    @MainActor
    func testMiniWindowFromAPrivateWindowIsNotPrivate() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        _ = openPrivateWindow(in: app)
        let mini = openMiniWindow(in: app)
        load("about:blank?mini", in: mini, app: app)
        let open = openInSpaceButton(in: mini)
        XCTAssertEqual(open.value as? String, "Perso")

        open.click()
        XCTAssertTrue(waitForCount(miniWindows(in: app), 0))
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertEqual(browserWindow(in: app).descendants(matching: .any).matching(identifier: "tabRow").count, 1)
    }

    /// Le raccourci global ouvre une mini-fenêtre depuis une autre app, une seule par appui, et Matcha au premier
    /// plan. ⌃⌥⌘F18 plutôt que ⌥⌘N : il ne gêne ni la Matcha de l'utilisateur ni une autre app. Si le raccourci
    /// n'arrive jamais (touches simulées par XCTest), ne pas affaiblir le test : le signaler.
    @MainActor
    func testGlobalShortcutOpensAMiniWindowFromAnotherApp() throws {
        // Constaté le 2026-10-17 : les touches simulées par XCTest vont droit à l'app visée et ne passent pas par
        // les raccourcis globaux du système ; le raccourci est vérifié à la main (TESTS_MANUELS.md, 4.5). Test gardé
        // pour un essai : MATCHA_TEST_GLOBAL_SHORTCUT=1.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MATCHA_TEST_GLOBAL_SHORTCUT"] != nil,
            "Touches simulées sans effet sur les raccourcis globaux",
        )
        let shortcut = Self.shortcutArgument(keyCode: 79, carbonModifiers: 6400)
        let app = launchApp(settings: ["KeyboardShortcuts_openMiniWindow": shortcut])
        XCTAssertTrue(waitForBrowserWindow(of: app))
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))

        finder.typeKey(.F18, modifierFlags: [.control, .option, .command])
        XCTAssertTrue(waitForCount(miniWindows(in: app), 1, timeout: 5))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(waitForKeyboardFocus(of: addressField(in: miniWindows(in: app).firstMatch)))

        // Matcha au premier plan : un appui, une seule mini-fenêtre de plus.
        app.typeKey(.F18, modifierFlags: [.control, .option, .command])
        XCTAssertTrue(waitForCount(miniWindows(in: app), 2, timeout: 5))
        sleep(1)
        XCTAssertEqual(miniWindows(in: app).count, 2)
    }
}
