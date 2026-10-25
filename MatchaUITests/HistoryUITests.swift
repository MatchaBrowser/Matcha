import XCTest

/// History (5.5): ⌘Y window, search, deletion, clearing, opening a row, private window and command bar. Pages:
/// the Postfix documentation shipped with macOS (no network); tests skipped if it is missing. These tests move
/// the real mouse.
final class HistoryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches the app and visits two pages of the Postfix documentation in the same tab.
    @MainActor
    private func launchAfterVisitingDocs() throws -> XCUIApplication {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        try visitLocalDocs(in: app)
        return app
    }

    @MainActor
    func testCommandYOpensTheHistoryWindowAndCommandWClosesIt() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        // Nothing opens by itself at launch.
        XCTAssertFalse(historyWindow(in: app).exists)

        let window = openHistoryWindow(in: app)
        XCTAssertTrue(historyEmptyState(in: window).waitForExistence(timeout: 5))
        XCTAssertEqual(historyRows(in: window).count, 0)
        // A single window: ⌘Y brings it back to the front.
        app.typeKey("y", modifierFlags: .command)
        XCTAssertEqual(app.windows.matching(NSPredicate(format: "title == %@", "Historique")).count, 1)

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(window.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["newTabButton"].exists)
    }

    @MainActor
    func testVisitedPagesAppearAndSearchFiltersThem() throws {
        let app = try launchAfterVisitingDocs()
        let window = openHistoryWindow(in: app)
        XCTAssertTrue(historyRow(titled: "Postfix Basic Configuration", in: window).waitForExistence(timeout: 5))
        XCTAssertTrue(historyRow(titled: "Postfix Documentation", in: window).exists)
        // The most recent first.
        XCTAssertEqual(historyRows(in: window).firstMatch.label, "Postfix Basic Configuration")
        XCTAssertEqual(historyRows(in: window).firstMatch.value as? String, "BASIC_CONFIGURATION_README.html")

        // Case- and accent-insensitive search, on the title and the address.
        let search = window.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("BASIC")
        XCTAssertTrue(waitForCount(historyRows(in: window), 1))
        XCTAssertEqual(historyRows(in: window).firstMatch.label, "Postfix Basic Configuration")
        search.typeKey("a", modifierFlags: .command)
        search.typeText("index.html")
        XCTAssertTrue(waitForCount(historyRows(in: window), 1))
        XCTAssertEqual(historyRows(in: window).firstMatch.label, "Postfix Documentation")
        search.typeKey("a", modifierFlags: .command)
        search.typeText("zzqqxx")
        XCTAssertTrue(waitForCount(historyRows(in: window), 0))
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(waitForCount(historyRows(in: window), 2))
    }

    @MainActor
    func testDeleteKeyAndContextMenuRemoveRows() throws {
        let app = try launchAfterVisitingDocs()
        let window = openHistoryWindow(in: app)
        let basic = historyRow(titled: "Postfix Basic Configuration", in: window)
        XCTAssertTrue(basic.waitForExistence(timeout: 5))

        basic.click()
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(basic.waitForNonExistence(timeout: 3))
        XCTAssertEqual(historyRows(in: window).count, 1)

        historyRow(titled: "Postfix Documentation", in: window).rightClick()
        // Row menu, in the window: “Edit > Delete” in the menu bar has the same title.
        window.menuItems["Supprimer"].click()
        XCTAssertTrue(historyEmptyState(in: window).waitForExistence(timeout: 3))
        // Deleted from the history, not from the sidebar.
        XCTAssertEqual(tabRows(in: app).count, 1)
    }

    @MainActor
    func testClearHistoryAsksForAPeriod() throws {
        let app = try launchAfterVisitingDocs()
        let window = openHistoryWindow(in: app)
        XCTAssertTrue(waitForCount(historyRows(in: window), 2, timeout: 5))
        let clear = window.buttons["historyClearButton"]

        // Cancel changes nothing.
        clear.click()
        let cancel = dialogButton("Annuler", in: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        XCTAssertTrue(dialogButton("La dernière heure", in: app).exists)
        XCTAssertTrue(dialogButton("Aujourd'hui et hier", in: app).exists)
        XCTAssertTrue(dialogButton("Tout l'historique", in: app).exists)
        cancel.click()
        XCTAssertEqual(historyRows(in: window).count, 2)

        clear.click()
        let today = dialogButton("Aujourd'hui", in: app)
        XCTAssertTrue(today.waitForExistence(timeout: 3))
        today.click()
        XCTAssertTrue(historyEmptyState(in: window).waitForExistence(timeout: 3))
    }

    @MainActor
    func testDoubleClickOpensTheRowInANewTabOfTheMainWindow() throws {
        let app = try launchAfterVisitingDocs()
        // No tab left: the page is now only in the history.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(tabRows(in: app), 0))

        let window = openHistoryWindow(in: app)
        let row = historyRow(titled: "Postfix Documentation", in: window)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.doubleClick()
        XCTAssertTrue(waitForCount(tabRows(in: app), 1, timeout: 5))
        XCTAssertTrue(waitForValue(of: addressPill(in: browserWindow(in: app)), timeout: 10) { $0 == "index.html" })
        // The main window came to the front: ⌘T opens the command bar there.
        openCommandBar(in: app, window: browserWindow(in: app))
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testPrivateWindowRecordsNothing() throws {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        try requireResource(FileManager.default.isReadableFile(atPath: Self.localDocsPath), "Postfix documentation missing")
        let privateWindow = openPrivateWindow(in: app)
        openCommandBar(in: app, window: privateWindow)
        app.typeText("file://\(Self.localDocsPath)\n")
        XCTAssertTrue(tabRow(titled: "Postfix Documentation", in: app).waitForExistence(timeout: 10))

        // “Show All History” is grayed out in a private window.
        app.menuBars.menuBarItems["Historique"].click()
        XCTAssertFalse(app.menuBars.menuItems["Afficher tout l'historique"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(privateWindow.waitForNonExistence(timeout: 5))
        let window = openHistoryWindow(in: app)
        XCTAssertTrue(historyEmptyState(in: window).waitForExistence(timeout: 5))
    }

    @MainActor
    func testCommandBarSuggestsAVisitedPageThatIsNoLongerOpen() throws {
        let app = try launchAfterVisitingDocs()
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(tabRows(in: app), 0))

        openCommandBar(in: app)
        app.typeText("postfix doc")
        let row = commandBarRows(in: app).matching(NSPredicate(format: "label == %@", "Postfix Documentation")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(waitForValue(of: addressPill(in: app), timeout: 10) { $0 == "index.html" })
    }
}
