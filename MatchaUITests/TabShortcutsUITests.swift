import XCTest

/// Tab shortcuts (4.8): ⌘1 to ⌘8 for Favorites then pinned tabs, ⌘9 for the last tab, ⌃⇥ and
/// ⌃⇧⇥ in sidebar order, wrapping around, pane by pane in a split; Tabs menu. Offline:
/// `about:blank?…`.
final class TabShortcutsUITests: XCTestCase {
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

    /// Waits for the pill of `scope` to show the tab `name`.
    @MainActor
    private func waitForDisplayed(_ name: String, in scope: XCUIElement) -> Bool {
        waitForValue(of: addressPill(in: scope)) { $0 == self.address(name) }
    }

    /// True if the pill of `scope` keeps the tab `name` for two seconds. XCTest only checks a wait
    /// after about 1 s: a shorter wait could never see a change.
    @MainActor
    private func keepsDisplaying(_ name: String, in scope: XCUIElement) -> Bool {
        !waitForValue(of: addressPill(in: scope), timeout: 2) { $0 != self.address(name) }
    }

    @MainActor
    func testCommandNumbersShowFavoritesThenPinnedAndCommandNineTheLastTab() {
        let app = launch(opening: ["one", "two", "three", "four"])
        tabRow(titled: address("one"), in: app).rightClick()
        app.menuItems["Ajouter aux favoris"].click()
        tabRow(titled: address("two"), in: app).rightClick()
        app.menuItems["Épingler"].click()
        // Favorite “one”, pinned “two”, Today tabs “four” (displayed) and “three”.
        XCTAssertTrue(waitForCount(tabRows(in: app), 3))

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(waitForDisplayed("one", in: app))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(waitForDisplayed("two", in: app))
        XCTAssertTrue(tabRow(titled: address("two"), in: app).isSelected)
        // No 3rd favorite nor 2nd pinned tab: ⌘3 does nothing (Today tabs aren't numbered).
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(keepsDisplaying("two", in: app))
        app.typeKey("9", modifierFlags: .command)
        XCTAssertTrue(waitForDisplayed("three", in: app))

        // Command bar open: ⌘1 closes it and shows the favorite.
        let field = openCommandBar(in: app)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForDisplayed("one", in: app))
    }

    @MainActor
    func testTabsMenuListsTheNumberedTabs() {
        let app = launch(opening: ["one", "two"])
        tabRow(titled: address("one"), in: app).rightClick()
        app.menuItems["Épingler"].click()
        XCTAssertTrue(waitForDisplayed("two", in: app))

        // Tabs menu only: the Window menu also lists the window under the title of the displayed tab.
        let menu = app.menuBars.menuBarItems["Onglets"]
        menu.click()
        XCTAssertTrue(menu.menuItems["Afficher l'onglet suivant"].waitForExistence(timeout: 3))
        XCTAssertTrue(menu.menuItems["Afficher l'onglet précédent"].exists)
        XCTAssertTrue(menu.menuItems["Afficher le dernier onglet"].exists)
        // Only the pinned tab is numbered; the Today tab isn't listed.
        XCTAssertFalse(menu.menuItems[address("two")].exists)
        menu.menuItems[address("one")].click()
        XCTAssertTrue(waitForDisplayed("one", in: app))
    }

    @MainActor
    func testControlTabWalksTheSidebarAndWrapsAround() {
        // Today tabs: “three” (displayed), “two”, “one”.
        let app = launch(opening: ["one", "two", "three"])
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(waitForDisplayed("two", in: app))
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(waitForDisplayed("one", in: app))
        // After the last one: the first one.
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(waitForDisplayed("three", in: app))
        XCTAssertTrue(tabRow(titled: address("three"), in: app).isSelected)
        // Before the first one: the last one.
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        XCTAssertTrue(waitForDisplayed("one", in: app))
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        XCTAssertTrue(waitForDisplayed("two", in: app))
    }

    @MainActor
    func testControlTabStepsThroughEachPaneOfASplit() {
        let app = launch(opening: ["one", "two", "three"])
        // Split “three | one” (active pane: “one”), then the tab “two”.
        openInSplit(address("one"), in: app)
        XCTAssertTrue(waitForCount(pagePanes(in: app), 2))
        XCTAssertTrue(waitForDisplayed("one", in: app))

        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(waitForDisplayed("two", in: app))
        XCTAssertTrue(waitForCount(pagePanes(in: app), 1))
        // Wrapping around, the split comes back through its first pane, then moves on to the second.
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(waitForDisplayed("three", in: app))
        XCTAssertTrue(waitForCount(pagePanes(in: app), 2))
        XCTAssertTrue(splitSegment(titled: address("three"), in: app).isSelected)
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(waitForDisplayed("one", in: app))
        XCTAssertTrue(splitSegment(titled: address("one"), in: app).isSelected)
        XCTAssertEqual(pagePanes(in: app).count, 2)
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        XCTAssertTrue(waitForDisplayed("three", in: app))
    }

    /// Mini window active: the shortcuts don't touch the browser window.
    @MainActor
    func testShortcutsDoNothingInAMiniWindow() {
        let app = launch(opening: ["one", "two"])
        tabRow(titled: address("one"), in: app).rightClick()
        app.menuItems["Épingler"].click()
        let browser = browserWindow(in: app)
        XCTAssertTrue(waitForDisplayed("two", in: browser))
        let mini = openMiniWindow(in: app)
        load(address("mini"), in: mini, app: app)

        app.typeKey(.tab, modifierFlags: .control)
        app.typeKey("1", modifierFlags: .command)
        app.typeKey("9", modifierFlags: .command)
        XCTAssertTrue(keepsDisplaying("two", in: browser))
        XCTAssertEqual(miniWindows(in: app).count, 1)
        XCTAssertTrue(waitForValue(of: addressPill(in: mini)) { $0 == self.address("mini") })
    }
}
