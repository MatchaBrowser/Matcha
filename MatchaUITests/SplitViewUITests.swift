import XCTest

/// Split view (4.3): creation from the menu and by dropping on the edge of a pane, active pane, removal,
/// separation, row dragged into the pinned tabs, divider, hidden sidebar. Offline: `about:blank?…`.
/// These tests move the real mouse.
final class SplitViewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches the app and opens one `about:blank?<name>` tab per name, in order: the last one is on top and
    /// displayed.
    @MainActor
    private func launch(opening names: [String]) -> XCUIApplication {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        for name in names {
            openAddress(address(name), in: app)
        }
        XCTAssertTrue(waitForCount(tabRows(in: app), names.count))
        return app
    }

    private func address(_ name: String) -> String {
        "about:blank?\(name)"
    }

    /// Titles of the panes, from left to right.
    @MainActor
    private func paneTitles(in app: XCUIApplication) -> [String] {
        orderedPagePanes(in: app).map(\.label)
    }

    @MainActor
    func testOpenInSplitFromTheMenuAndTheAddressFollowsTheActivePane() {
        let app = launch(opening: ["one", "two"])
        openInSplit(address("one"), in: app)
        XCTAssertTrue(waitForCount(pagePanes(in: app), 2))
        XCTAssertEqual(splitRows(in: app).count, 1)
        XCTAssertEqual(tabRows(in: app).count, 0)
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == self.address("one") })
        XCTAssertTrue(splitSegment(titled: address("one"), in: app).isSelected)
        XCTAssertEqual(paneTitles(in: app), [address("two"), address("one")])

        // A click in the left page makes it the active pane; the pill follows it.
        let left = orderedPagePanes(in: app)[0]
        left.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == self.address("two") })
        XCTAssertTrue(splitSegment(titled: address("two"), in: app).isSelected)

        // ⌘W closes the active pane; down to one tab, the split goes away.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(pagePanes(in: app), 1))
        XCTAssertTrue(waitForCount(splitRows(in: app), 0))
        XCTAssertEqual(tabRows(in: app).count, 1)
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == self.address("one") })
    }

    /// Gate S1 and S3: a tab dropped on the edge of a pane joins the split on that side.
    @MainActor
    func testDroppingTabsOnPaneEdgesBuildsASplit() {
        let app = launch(opening: ["one", "two", "three"])
        let pane = orderedPagePanes(in: app)[0]
        dragTab(titled: address("one"), to: pane.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)), in: app)
        XCTAssertTrue(waitForCount(pagePanes(in: app), 2))
        XCTAssertEqual(paneTitles(in: app), [address("three"), address("one")])

        let leftmost = orderedPagePanes(in: app)[0]
        dragTab(titled: address("two"), to: leftmost.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)), in: app)
        XCTAssertTrue(waitForCount(pagePanes(in: app), 3))
        XCTAssertEqual(paneTitles(in: app), [address("two"), address("three"), address("one")])
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == self.address("two") })
        XCTAssertEqual(tabRows(in: app).count, 0)
    }

    @MainActor
    func testDroppingInTheMiddleOfAPageDoesNothing() {
        let app = launch(opening: ["one", "two"])
        let pane = orderedPagePanes(in: app)[0]
        dragTab(titled: address("one"), to: pane.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), in: app)
        // XCTest only checks a wait after about 1 s: 2 s at least, otherwise the wait can't succeed.
        XCTAssertFalse(waitForCount(pagePanes(in: app), 2, timeout: 2))
        XCTAssertEqual(pagePanes(in: app).count, 1)
        XCTAssertEqual(tabRows(in: app).count, 2)
        XCTAssertEqual(splitRows(in: app).count, 0)
    }

    @MainActor
    func testASplitHoldsAtMostFourTabs() {
        let app = launch(opening: ["one", "two", "three", "four", "five"])
        for name in ["four", "three", "two"] {
            openInSplit(address(name), in: app)
        }
        XCTAssertTrue(waitForCount(pagePanes(in: app), 4))
        // Full split: the item is grayed out, not missing.
        tabRow(titled: address("one"), in: app).rightClick()
        let item = app.menuItems["Ouvrir en split"]
        XCTAssertTrue(item.waitForExistence(timeout: 2))
        XCTAssertFalse(item.isEnabled)
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testRemoveFromSplitAndSeparateTabs() {
        let app = launch(opening: ["one", "two", "three"])
        openInSplit(address("one"), in: app)
        openInSplit(address("two"), in: app)
        XCTAssertTrue(waitForCount(pagePanes(in: app), 3))

        splitSegment(titled: address("one"), in: app).rightClick()
        app.menuItems["Retirer du split"].click()
        XCTAssertTrue(waitForCount(pagePanes(in: app), 2))
        XCTAssertEqual(tabRows(in: app).count, 1)

        splitSegments(in: app).firstMatch.rightClick()
        app.menuItems["Séparer les onglets"].click()
        XCTAssertTrue(waitForCount(splitRows(in: app), 0))
        XCTAssertTrue(waitForCount(tabRows(in: app), 3))
        XCTAssertEqual(pagePanes(in: app).count, 1)
    }

    /// Gate S2 for the `.split` item: the row is dragged as a whole.
    @MainActor
    func testDraggingASplitRowToPinnedKeepsItTogether() {
        let app = launch(opening: ["one", "two", "three"])
        openInSplit(address("two"), in: app)
        XCTAssertTrue(waitForCount(splitRows(in: app), 1))
        let pinnedZone = app.descendants(matching: .any).matching(identifier: "pinnedDropZone").firstMatch
        splitRows(in: app).firstMatch.press(forDuration: 0.5, thenDragTo: pinnedZone)
        // The pinned split survives “Clear”, which only closes Today tabs.
        clickWhenSettled(app.buttons["Effacer"])
        XCTAssertTrue(waitForCount(tabRows(in: app), 0))
        XCTAssertEqual(splitRows(in: app).count, 1)
        XCTAssertEqual(splitSegments(in: app).count, 2)

        // ⌘W unloads the whole pinned split, which stays in the sidebar.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(pagePanes(in: app), 1))
        XCTAssertTrue(app.staticTexts["Aucun onglet"].waitForExistence(timeout: 2))
        XCTAssertTrue(splitRows(in: app).firstMatch.exists)

        splitSegments(in: app).firstMatch.click()
        XCTAssertTrue(waitForCount(pagePanes(in: app), 2))
    }

    @MainActor
    func testDividerKeepsMinimumWidthsAndDoubleClickEqualizes() {
        let app = launch(opening: ["one", "two"])
        openInSplit(address("one"), in: app)
        XCTAssertTrue(waitForCount(pagePanes(in: app), 2))
        let divider = splitDivider(in: app)
        XCTAssertTrue(divider.waitForExistence(timeout: 2))

        drag(divider, by: 1000)
        XCTAssertEqual(orderedPagePanes(in: app)[1].frame.width, 200, accuracy: 2)
        drag(divider, by: -2000)
        XCTAssertEqual(orderedPagePanes(in: app)[0].frame.width, 200, accuracy: 2)
        divider.doubleClick()
        let panes = orderedPagePanes(in: app)
        XCTAssertEqual(panes[0].frame.width, panes[1].frame.width, accuracy: 2)
    }

    @MainActor
    func testSplitFillsTheCardWithTheSidebarHidden() {
        let app = launch(opening: ["one", "two"])
        openInSplit(address("one"), in: app)
        XCTAssertTrue(waitForCount(pagePanes(in: app), 2))
        let window = app.windows.firstMatch
        moveAwayFromLeftEdge(in: window)
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(app.buttons["newTabButton"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(pagePanes(in: app).count, 2)
        XCTAssertLessThanOrEqual(orderedPagePanes(in: app)[0].frame.minX - window.frame.minX, 12)
    }
}
