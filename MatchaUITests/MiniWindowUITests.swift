import XCTest

/// Mini window (equivalent of Little Arc). Opened from the File menu: the global shortcut is turned off by the
/// launch settings (`defaultSettings`), except in the test that checks it, which picks one that nobody uses
/// (⌃⌥⌘F18). These tests activate the Finder and use the real mouse.
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

        // The page stays in the mini window: no tab in the sidebar.
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
        // Browser window active: the mini window stays in front of it.
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
        // Same web view: the history came along (a tab recreated from the address wouldn't have it).
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

        app.typeKey("o", modifierFlags: [.command, .shift])
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

    /// The global shortcut opens a mini window from another app, only one per press, with Matcha in front.
    /// ⌃⌥⌘F18 rather than ⌥⌘N: it gets in the way of neither the user's Matcha nor another app. If the shortcut
    /// never arrives (keys simulated by XCTest), don't weaken the test: report it.
    @MainActor
    func testGlobalShortcutOpensAMiniWindowFromAnotherApp() throws {
        // Observed on 2026-10-17: keys simulated by XCTest go straight to the target app and don't go through the
        // system's global shortcuts; the shortcut is checked by hand (TESTS_MANUELS.md, 4.5). Test kept for a trial:
        // MATCHA_TEST_GLOBAL_SHORTCUT=1.
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

        // Matcha in front: one press, exactly one more mini window.
        app.typeKey(.F18, modifierFlags: [.control, .option, .command])
        XCTAssertTrue(waitForCount(miniWindows(in: app), 2, timeout: 5))
        sleep(1)
        XCTAssertEqual(miniWindows(in: app).count, 2)
    }
}
