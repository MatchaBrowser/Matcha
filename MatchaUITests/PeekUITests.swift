import XCTest

/// Peek (4.4): Shift-click, closing (⎋, ⌘W, ×, click beside it, another tab, command bar), “Open as Tab” and
/// split view. Pages: the Postfix documentation shipped with macOS (no network).
/// These tests move the real mouse and hold the Shift key.
final class PeekUITests: XCTestCase {
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
    func testShiftClickOpensPeekAndEscapeClosesIt() throws {
        let app = try launchOnLocalDocs()
        openPeekOnLocalDocs(in: app)
        // Neither a tab nor a navigation: the original page stays displayed behind.
        XCTAssertEqual(tabRows(in: app).count, 1)
        XCTAssertEqual(addressPill(in: app).value as? String, "index.html")

        // The Peek page has keyboard focus and doesn't keep ⎋: the Peek closes.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(peekElement("peekCloseButton", in: app).waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 1)
        XCTAssertEqual(addressPill(in: app).value as? String, "index.html")
    }

    @MainActor
    func testOpenAsTabKeepsThePageAndItsHistory() throws {
        let app = try launchOnLocalDocs()
        openPeekOnLocalDocs(in: app)

        // A link in the Peek loads there.
        clickWhenSettled(links("main.cf", exact: true, in: app).firstMatch)
        XCTAssertTrue(waitForValue(of: peekElement("peekAddress", in: app), timeout: 10) { $0 == "postconf.5.html" })
        XCTAssertEqual(tabRows(in: app).count, 1)

        peekElement("peekOpenAsTabButton", in: app).click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        XCTAssertTrue(peekElement("peekCloseButton", in: app).waitForNonExistence(timeout: 3))
        let pill = addressPill(in: app)
        XCTAssertTrue(waitForValue(of: pill) { $0 == "postconf.5.html" })

        // Same web view: the Peek's history is there.
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(waitForValue(of: pill) { $0 == "BASIC_CONFIGURATION_README.html" })

        tabRow(titled: "Postfix Documentation", in: app).click()
        XCTAssertTrue(waitForValue(of: pill) { $0 == "index.html" })
    }

    @MainActor
    func testClickBesideThePeekClosesItWithoutTouchingThePage() throws {
        let app = try launchOnLocalDocs()
        let sourceFrame = link(containing: "Basic configuration", in: app).frame
        openPeekOnLocalDocs(in: app)

        // On the scrim, left of the panel; if possible right above the original link, which must not be followed.
        let window = app.windows.firstMatch
        let address = peekElement("peekAddress", in: app)
        // End of the opening animation: the bar is in place.
        Thread.sleep(forTimeInterval: 0.6)
        let sourceIsVisible = sourceFrame.midY > window.frame.minY && sourceFrame.midY < window.frame.maxY
        let target = CGPoint(x: address.frame.minX - 6, y: sourceIsVisible ? sourceFrame.midY : address.frame.midY)
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: target.x - window.frame.minX, dy: target.y - window.frame.minY))
            .click()

        XCTAssertTrue(peekElement("peekCloseButton", in: app).waitForNonExistence(timeout: 3))
        sleep(1)
        XCTAssertEqual(addressPill(in: app).value as? String, "index.html")
        XCTAssertEqual(tabRows(in: app).count, 1)
    }

    @MainActor
    func testCommandWAndCloseButtonCloseThePeekNotTheTab() throws {
        let app = try launchOnLocalDocs()
        openPeekOnLocalDocs(in: app)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(peekElement("peekCloseButton", in: app).waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 1)

        openPeekOnLocalDocs(in: app)
        clickWhenSettled(peekElement("peekCloseButton", in: app))
        XCTAssertTrue(peekElement("peekCloseButton", in: app).waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 1)
        XCTAssertEqual(addressPill(in: app).value as? String, "index.html")
    }

    @MainActor
    func testSelectingAnotherTabOrOpeningTheCommandBarClosesThePeek() throws {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        try openLocalDocs(in: app)
        openPeekOnLocalDocs(in: app)

        tabRow(titled: "Nouvel onglet", in: app).click()
        XCTAssertTrue(peekElement("peekCloseButton", in: app).waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 2)
        XCTAssertTrue(waitForEmptyValue(of: addressPill(in: app)))

        tabRow(titled: "Postfix Documentation", in: app).click()
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "index.html" })
        openPeekOnLocalDocs(in: app)
        let field = openCommandBar(in: app, newTab: false)
        XCTAssertFalse(peekElement("peekCloseButton", in: app).exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }

    /// Split of two pages: the Peek opens from the left pane; “Open as Tab” moves the page out of the split,
    /// displayed alone.
    @MainActor
    func testPeekOverASplitOpensAsATabOutsideTheSplit() throws {
        let app = try launchOnLocalDocs()
        try openLocalDocs(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        let background = try XCTUnwrap(tabRows(in: app).allElementsBoundByIndex.first { !$0.isSelected })
        background.rightClick()
        app.menuItems["Ouvrir en split"].click()
        XCTAssertTrue(waitForCount(pagePanes(in: app), 2))

        // Link of the left pane, which isn't the active pane: the click activates it, then the Peek opens.
        let sources = links("Basic configuration", in: app).allElementsBoundByIndex
        let leftSource = try XCTUnwrap(sources.min { $0.frame.minX < $1.frame.minX })
        shiftClick(leftSource)
        XCTAssertTrue(peekElement("peekCloseButton", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: peekElement("peekAddress", in: app), timeout: 10) { $0 == "BASIC_CONFIGURATION_README.html" })
        XCTAssertEqual(pagePanes(in: app).count, 2)

        clickWhenSettled(peekElement("peekOpenAsTabButton", in: app))
        XCTAssertTrue(waitForCount(pagePanes(in: app), 1))
        XCTAssertEqual(splitRows(in: app).count, 1)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "BASIC_CONFIGURATION_README.html" })
    }
}
