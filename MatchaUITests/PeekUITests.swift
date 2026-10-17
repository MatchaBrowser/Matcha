import XCTest

/// Aperçu (Peek, 4.4) : Maj+clic, fermeture (⎋, ⌘W, ×, clic à côté, autre onglet, barre de commande),
/// « Ouvrir en onglet » et split view. Pages : la documentation de Postfix livrée avec macOS (sans réseau).
/// Ces tests déplacent la vraie souris et tiennent la touche Maj.
final class PeekUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Lance l'app sur la page d'accueil de la documentation de Postfix, seule dans la barre.
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
        // Ni onglet ni navigation : la page d'origine reste affichée derrière.
        XCTAssertEqual(tabRows(in: app).count, 1)
        XCTAssertEqual(addressPill(in: app).value as? String, "index.html")

        // La page de l'aperçu a le clavier et ne garde pas ⎋ : l'aperçu se ferme.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(peekElement("peekCloseButton", in: app).waitForNonExistence(timeout: 3))
        XCTAssertEqual(tabRows(in: app).count, 1)
        XCTAssertEqual(addressPill(in: app).value as? String, "index.html")
    }

    @MainActor
    func testOpenAsTabKeepsThePageAndItsHistory() throws {
        let app = try launchOnLocalDocs()
        openPeekOnLocalDocs(in: app)

        // Un lien dans l'aperçu s'y charge.
        clickWhenSettled(links("main.cf", exact: true, in: app).firstMatch)
        XCTAssertTrue(waitForValue(of: peekElement("peekAddress", in: app), timeout: 10) { $0 == "postconf.5.html" })
        XCTAssertEqual(tabRows(in: app).count, 1)

        peekElement("peekOpenAsTabButton", in: app).click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        XCTAssertTrue(peekElement("peekCloseButton", in: app).waitForNonExistence(timeout: 3))
        let pill = addressPill(in: app)
        XCTAssertTrue(waitForValue(of: pill) { $0 == "postconf.5.html" })

        // Même vue web : l'historique de l'aperçu est là.
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

        // Sur le voile, à gauche du panneau ; si possible juste au-dessus du lien d'origine, qui ne doit pas être suivi.
        let window = app.windows.firstMatch
        let address = peekElement("peekAddress", in: app)
        // Fin de l'animation d'ouverture : la barre est à sa place.
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

    /// Split de deux pages : l'aperçu s'ouvre depuis le panneau de gauche ; « Ouvrir en onglet » range la page
    /// hors du split, affichée seule.
    @MainActor
    func testPeekOverASplitOpensAsATabOutsideTheSplit() throws {
        let app = try launchOnLocalDocs()
        try openLocalDocs(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        let background = try XCTUnwrap(tabRows(in: app).allElementsBoundByIndex.first { !$0.isSelected })
        background.rightClick()
        app.menuItems["Ouvrir en split"].click()
        XCTAssertTrue(waitForCount(pagePanes(in: app), 2))

        // Lien du panneau de gauche, qui n'est pas le panneau actif : le clic l'active, puis l'aperçu s'ouvre.
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
