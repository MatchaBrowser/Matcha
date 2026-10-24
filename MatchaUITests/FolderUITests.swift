import XCTest

/// Pinned folders: creation, renaming, filing, collapsing, nesting.
final class FolderUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func folderRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "folderRow")
    }

    /// Creates a folder through the `menuItem` menu item of `element` and names it `name`.
    @MainActor
    private func createFolder(named name: String, from element: XCUIElement, menuItem: String, in app: XCUIApplication) {
        element.rightClick()
        app.menuItems[menuItem].click()
        let field = app.textFields["folderNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        app.typeText("\(name)\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }

    /// Drags `element` to the middle of `row` at `height` (0: top, 1: bottom), slowly, with a pause on arrival: the row
    /// has time to follow the pointer.
    @MainActor
    private func drag(_ element: XCUIElement, to row: XCUIElement, at height: CGFloat) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.5,
            thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: height)),
            withVelocity: .slow,
            thenHoldForDuration: 0.5,
        )
    }

    /// Waits for `condition`, checked again while the sidebar settles after a drop.
    @MainActor
    private func waitFor(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                return false
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return true
    }

    /// The edges of the rows: before the first folder of the pinned items, after the last tab of a folder, between two
    /// folders. The tabs all have the same title: the selected one is followed by its trait, the others by position.
    @MainActor
    func testDroppingBeforeAfterAndBetweenFolders() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        for _ in 0 ..< 4 {
            openEmptyTab(in: app)
        }
        let rows = tabRows(in: app)
        XCTAssertTrue(waitForCount(rows, 4))
        rows.element(boundBy: 0).rightClick()
        app.menuItems["Épingler"].click()
        let pinned = rows.element(boundBy: 0)
        createFolder(named: "Travail", from: pinned, menuItem: "Nouveau dossier", in: app)
        createFolder(named: "Perso", from: pinned, menuItem: "Nouveau dossier", in: app)
        let work = folderRows(in: app).matching(NSPredicate(format: "label == %@", "Travail")).firstMatch
        let personal = folderRows(in: app).matching(NSPredicate(format: "label == %@", "Perso")).firstMatch
        // The pinned items start with a folder: Travail (the pinned tab), Perso.
        drag(pinned, to: work, at: 0.5)
        XCTAssertTrue(waitFor { rows.element(boundBy: 0).frame.minY > work.frame.maxY - 1 })

        // Top of the first folder: the last today tab (not the selected one) becomes the first pinned item.
        drag(rows.element(boundBy: 3), to: work, at: 0.15)
        XCTAssertTrue(waitFor { rows.element(boundBy: 0).frame.maxY < work.frame.minY + 1 })

        // Bottom of the last tab of the folder: the selected tab goes into it, after that tab.
        let selected = rows.matching(NSPredicate(format: "selected == true")).firstMatch
        drag(selected, to: rows.element(boundBy: 1), at: 0.85)
        XCTAssertTrue(waitFor { rows.element(boundBy: 2).isSelected })
        clickWhenSettled(work)
        XCTAssertTrue(waitForCount(rows, 2), "onglets visibles : \(rows.count)")

        // Bottom of the collapsed folder: the last today tab goes between the two folders.
        drag(rows.element(boundBy: 1), to: work, at: 0.85)
        XCTAssertTrue(waitFor {
            rows.allElementsBoundByIndex.contains { $0.frame.minY > work.frame.maxY - 1 && $0.frame.maxY < personal.frame.minY + 1 }
        })
    }

    @MainActor
    func testCreateFillCollapseAndNestFolders() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Épingler"].click()

        // The folder is created from the pinned tab, then named.
        let pinned = tabRows(in: app).firstMatch
        createFolder(named: "Travail", from: pinned, menuItem: "Nouveau dossier", in: app)
        let folder = folderRows(in: app).firstMatch
        XCTAssertEqual(folder.label, "Travail")

        // The pinned tab, dropped on the middle of the folder row, goes into it; collapsing the folder hides it.
        pinned.press(forDuration: 0.5, thenDragTo: folder)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        folder.click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        folder.click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))

        // Subfolder: collapsing the parent also hides the subfolder.
        createFolder(named: "Client", from: folder, menuItem: "Nouveau sous-dossier", in: app)
        XCTAssertTrue(waitForCount(folderRows(in: app), 2))
        folder.click()
        XCTAssertTrue(waitForCount(folderRows(in: app), 1))
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
    }

    @MainActor
    func testEscapeKeepsTheDefaultName() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Épingler"].click()
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Nouveau dossier"].click()
        let field = app.textFields["folderNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertEqual(folderRows(in: app).firstMatch.label, "Nouveau dossier")
    }
}
