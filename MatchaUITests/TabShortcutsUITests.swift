import XCTest

/// Raccourcis des onglets (4.8) : ⌘1 à ⌘8 pour les favoris puis les épinglés, ⌘9 pour le dernier onglet, ⌃⇥ et
/// ⌃⇧⇥ dans l'ordre de la barre, en boucle, panneau par panneau dans un split ; menu Onglets. Hors ligne :
/// `about:blank?…`.
final class TabShortcutsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Lance l'app et ouvre un onglet `about:blank?<nom>` par nom, dans l'ordre : le dernier est en tête et
    /// affiché.
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

    /// Attend que la pastille de `scope` affiche l'onglet `name`.
    @MainActor
    private func waitForDisplayed(_ name: String, in scope: XCUIElement) -> Bool {
        waitForValue(of: addressPill(in: scope)) { $0 == self.address(name) }
    }

    /// Vrai si la pastille de `scope` garde l'onglet `name` pendant deux secondes. XCTest ne vérifie une attente
    /// qu'au bout d'environ 1 s : une attente plus courte ne pourrait jamais voir de changement.
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
        // Favori « one », épinglé « two », onglets du jour « four » (affiché) et « three ».
        XCTAssertTrue(waitForCount(tabRows(in: app), 3))

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(waitForDisplayed("one", in: app))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(waitForDisplayed("two", in: app))
        XCTAssertTrue(tabRow(titled: address("two"), in: app).isSelected)
        // Ni 3ᵉ favori ni 2ᵉ épinglé : ⌘3 ne fait rien (les onglets du jour ne sont pas numérotés).
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(keepsDisplaying("two", in: app))
        app.typeKey("9", modifierFlags: .command)
        XCTAssertTrue(waitForDisplayed("three", in: app))

        // Barre de commande ouverte : ⌘1 la ferme et affiche le favori.
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

        // Menu Onglets seulement : le menu Fenêtre liste aussi la fenêtre sous le titre de l'onglet affiché.
        let menu = app.menuBars.menuBarItems["Onglets"]
        menu.click()
        XCTAssertTrue(menu.menuItems["Afficher l'onglet suivant"].waitForExistence(timeout: 3))
        XCTAssertTrue(menu.menuItems["Afficher l'onglet précédent"].exists)
        XCTAssertTrue(menu.menuItems["Afficher le dernier onglet"].exists)
        // Seul l'épinglé est numéroté ; l'onglet du jour n'est pas listé.
        XCTAssertFalse(menu.menuItems[address("two")].exists)
        menu.menuItems[address("one")].click()
        XCTAssertTrue(waitForDisplayed("one", in: app))
    }

    @MainActor
    func testControlTabWalksTheSidebarAndWrapsAround() {
        // Onglets du jour : « three » (affiché), « two », « one ».
        let app = launch(opening: ["one", "two", "three"])
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(waitForDisplayed("two", in: app))
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(waitForDisplayed("one", in: app))
        // Après le dernier : le premier.
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(waitForDisplayed("three", in: app))
        XCTAssertTrue(tabRow(titled: address("three"), in: app).isSelected)
        // Avant le premier : le dernier.
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        XCTAssertTrue(waitForDisplayed("one", in: app))
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        XCTAssertTrue(waitForDisplayed("two", in: app))
    }

    @MainActor
    func testControlTabStepsThroughEachPaneOfASplit() {
        let app = launch(opening: ["one", "two", "three"])
        // Split « three | one » (panneau actif : « one »), puis l'onglet « two ».
        openInSplit(address("one"), in: app)
        XCTAssertTrue(waitForCount(pagePanes(in: app), 2))
        XCTAssertTrue(waitForDisplayed("one", in: app))

        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(waitForDisplayed("two", in: app))
        XCTAssertTrue(waitForCount(pagePanes(in: app), 1))
        // En boucle, le split revient par son premier panneau, puis passe au second.
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

    /// Mini-fenêtre active : les raccourcis ne touchent pas à la fenêtre de navigation.
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
