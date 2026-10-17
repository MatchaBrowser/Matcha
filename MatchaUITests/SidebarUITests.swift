import XCTest

/// Barre latérale : disposition, rangement des onglets, glisser-déposer.
final class SidebarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddressPillStaysAtTheTopWithoutPage() {
        let app = launchApp()
        let pill = addressPill(in: app)
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch
        // Sans onglet puis avec un onglet vide, la pastille reste sous la barre de titre, pas au milieu.
        XCTAssertLessThan(pill.frame.minY - window.frame.minY, 120)
        openEmptyTab(in: app)
        XCTAssertLessThan(pill.frame.minY - window.frame.minY, 120)
    }

    @MainActor
    func testDraggingTheSidebarEdgeResizesItWithoutMovingTheWindow() {
        let app = launchApp()
        let window = app.windows.firstMatch
        let handle = app.descendants(matching: .any).matching(identifier: "sidebarResizeHandle").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let windowFrame = window.frame
        let startX = handle.frame.midX

        drag(handle, by: 60)
        XCTAssertEqual(window.frame, windowFrame)
        XCTAssertEqual(handle.frame.midX - startX, 60, accuracy: 2)

        // Largeur plafonnée à 400 pt.
        drag(handle, by: 1000)
        XCTAssertEqual(handle.frame.midX - window.frame.minX, 400, accuracy: 2)

        // Rend la largeur d'origine : elle est mémorisée d'un lancement à l'autre.
        drag(handle, by: startX - handle.frame.midX)
        XCTAssertEqual(handle.frame.midX, startX, accuracy: 2)
    }

    @MainActor
    func testDraggingTheEmptyTopOfTheSidebarMovesTheWindow() {
        let app = launchApp()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let start = window.frame
        // Zone vide sous la barre de titre, à droite des boutons de la fenêtre.
        let emptyArea = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 150, dy: 34))
        // Glissement horizontal : verticalement, macOS contraint la fenêtre (barre des menus, aimantation).
        emptyArea.press(forDuration: 0.2, thenDragTo: emptyArea.withOffset(CGVector(dx: 60, dy: 0)))
        // La fenêtre suit le geste, à un petit seuil de départ près.
        XCTAssertGreaterThan(window.frame.minX - start.minX, 20)
    }

    @MainActor
    func testFavoritesAndClearingTodayTabs() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        for _ in 0 ..< 3 {
            openEmptyTab(in: app)
        }
        XCTAssertTrue(waitForCount(tabRows(in: app), 3))

        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Ajouter aux favoris"].click()
        let favorites = app.descendants(matching: .any).matching(identifier: "favoriteTile")
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(tabRows(in: app).count, 2)

        app.buttons["Effacer"].click()
        XCTAssertEqual(tabRows(in: app).count, 0)
        XCTAssertEqual(favorites.count, 1)
    }

    @MainActor
    func testDraggingTabsToFavoritesAndPinned() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        for _ in 0 ..< 3 {
            openEmptyTab(in: app)
        }
        XCTAssertTrue(waitForCount(tabRows(in: app), 3))

        let favoritesZone = app.descendants(matching: .any).matching(identifier: "favoritesDropZone").firstMatch
        tabRows(in: app).element(boundBy: 0).press(forDuration: 0.5, thenDragTo: favoritesZone)
        let favorites = app.descendants(matching: .any).matching(identifier: "favoriteTile")
        XCTAssertTrue(favorites.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 2)

        let pinnedZone = app.descendants(matching: .any).matching(identifier: "pinnedDropZone").firstMatch
        tabRows(in: app).element(boundBy: 1).press(forDuration: 0.5, thenDragTo: pinnedZone)
        // L'onglet épinglé survit à « Effacer », qui ne ferme que les onglets du jour.
        app.buttons["Effacer"].click()
        XCTAssertEqual(tabRows(in: app).count, 1)
        XCTAssertEqual(favorites.count, 1)
    }

    @MainActor
    func testNewTabButtonAddsTabs() {
        let app = launchApp()
        let newTabButton = app.buttons["newTabButton"]
        let field = addressField(in: app)
        XCTAssertTrue(newTabButton.waitForExistence(timeout: 5))
        // Le bouton ouvre la barre de commande ; Entrée sans texte crée l'onglet.
        newTabButton.click()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        XCTAssertEqual(tabRows(in: app).count, 0)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        newTabButton.click()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
    }

    @MainActor
    func testContextMenuDuplicatesAndClosesOtherTabs() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        for _ in 0 ..< 3 {
            openEmptyTab(in: app)
        }
        XCTAssertTrue(waitForCount(tabRows(in: app), 3))
        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Dupliquer"].click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 4))

        tabRows(in: app).firstMatch.rightClick()
        app.menuItems["Fermer les autres onglets"].click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
    }
}
