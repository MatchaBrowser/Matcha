import XCTest

/// Find in page (5.3): ⌘F, search as you type, “Not Found”, ⌘G and ⇧⌘G, ⎋, tab switch, Peek. Pages: the
/// stand-in of the Postfix documentation written by the tests (`UITestPages`, no network). These tests move the
/// real mouse.
final class FindInPageUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches the app on the home page of the Postfix documentation, alone in the sidebar.
    @MainActor
    private func launchOnLocalDocs() throws -> XCUIApplication {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        try openLocalDocs(in: app)
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "index.html" })
        return app
    }

    @MainActor
    func testCommandFOpensTheBarAndTypingSearches() throws {
        let app = try launchOnLocalDocs()
        let field = openFindBar(in: app)
        app.typeText("postfix")
        XCTAssertTrue(waitForValue(of: field) { $0 == "postfix" })
        XCTAssertFalse(findStatus(in: app).waitForExistence(timeout: 2), "“postfix” is in the page")

        replaceFindText(with: "zzqqxx", in: app)
        XCTAssertTrue(waitForNotFound(in: app))

        // Field cleared: no result anymore.
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(findStatus(in: app).waitForNonExistence(timeout: 3))

        // ⌘F, bar already open: the field keeps keyboard focus.
        openFindBar(in: app)
    }

    @MainActor
    func testNextAndPreviousKeepTheBarOpen() throws {
        let app = try launchOnLocalDocs()
        let field = openFindBar(in: app)
        app.typeText("postfix")
        XCTAssertFalse(findStatus(in: app).waitForExistence(timeout: 2))

        app.typeKey("g", modifierFlags: .command)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: .shift)
        findButton("findNextButton", in: app).click()
        findButton("findPreviousButton", in: app).click()

        XCTAssertTrue(field.exists)
        XCTAssertEqual(field.value as? String, "postfix")
        XCTAssertFalse(findStatus(in: app).exists)
        XCTAssertEqual(tabRows(in: app).count, 1)
        XCTAssertEqual(addressPill(in: app).value as? String, "index.html")
    }

    @MainActor
    func testEscapeClosesTheBarAndThePageKeepsWorking() throws {
        let app = try launchOnLocalDocs()
        let field = openFindBar(in: app)
        app.typeText("configuration")
        XCTAssertFalse(findStatus(in: app).waitForExistence(timeout: 2))

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))

        // ⌘G reopens the bar with the same text, without giving it keyboard focus; × closes it again.
        app.typeKey("g", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "configuration")
        findButton("findCloseButton", in: app).click()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))

        // The page still responds: a link opens.
        clickWhenSettled(link(containing: "Basic configuration", in: app))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "BASIC_CONFIGURATION_README.html" })
    }

    @MainActor
    func testSwitchingTabHidesTheBarUntilComingBack() throws {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        try openLocalDocs(in: app)
        let field = openFindBar(in: app)
        app.typeText("postfix")
        XCTAssertTrue(waitForValue(of: field) { $0 == "postfix" })

        tabRow(titled: "Nouvel onglet", in: app).click()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        // Empty tab: nothing to search, ⌘F opens nothing.
        app.typeKey("f", modifierFlags: .command)
        XCTAssertFalse(field.waitForExistence(timeout: 1))

        // Back again, the bar is there, with its text.
        tabRow(titled: "Postfix Documentation", in: app).click()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "postfix")
    }

    /// Peek open: ⌘F searches its page; ⎋ closes the bar, not the Peek, then a second ⎋ closes the Peek.
    @MainActor
    func testFindInPeekAndEscapeClosesOnlyTheBar() throws {
        let app = try launchOnLocalDocs()
        openPeekOnLocalDocs(in: app)
        let field = openFindBar(in: app)
        // In the Peek panel, below its bar.
        XCTAssertGreaterThan(field.frame.minY, peekElement("peekAddress", in: app).frame.maxY)
        app.typeText("postfix")
        XCTAssertFalse(findStatus(in: app).waitForExistence(timeout: 2))

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertTrue(peekElement("peekCloseButton", in: app).exists)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(peekElement("peekCloseButton", in: app).waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 1)
        XCTAssertEqual(addressPill(in: app).value as? String, "index.html")
    }
}
