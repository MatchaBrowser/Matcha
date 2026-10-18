import XCTest

/// Menu contextuel des pages (5.9) : « Ouvrir le lien dans un nouvel onglet », « Ouvrir dans un aperçu » et « Ouvrir
/// l'image dans un nouvel onglet », depuis un onglet, l'aperçu et une mini-fenêtre. Pages : la documentation de
/// Postfix livrée avec macOS (sans réseau). Ces tests déplacent la vraie souris.
final class PageMenuUITests: XCTestCase {
    private static let newTabItem = "Ouvrir le lien dans un nouvel onglet"
    private static let peekItem = "Ouvrir dans un aperçu"
    private static let imageItem = "Ouvrir l'image dans un nouvel onglet"

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

    /// Élément du menu contextuel ouvert, par son titre.
    @MainActor
    private func menuItem(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.menuItems.matching(NSPredicate(format: "title == %@", title)).firstMatch
    }

    /// Clic droit au centre du lien `element` une fois sa position stable (aperçu qui s'ouvre), par coordonnées : un
    /// lien de page est entièrement couvert par son texte. Le menu du lien s'ouvre.
    @MainActor
    private func rightClickWhenSettled(_ element: XCUIElement, in app: XCUIApplication) {
        var previous = element.frame
        for _ in 0 ..< 12 {
            Thread.sleep(forTimeInterval: 0.25)
            if element.frame == previous {
                break
            }
            previous = element.frame
        }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        XCTAssertTrue(menuItem(Self.newTabItem, in: app).waitForExistence(timeout: 3))
    }

    @MainActor
    func testOpenLinkInNewTabOpensABackgroundTabAfterThePage() throws {
        let app = try launchOnLocalDocs()
        rightClickWhenSettled(link(containing: "Basic configuration", in: app), in: app)
        XCTAssertTrue(menuItem(Self.peekItem, in: app).exists)
        menuItem(Self.newTabItem, in: app).click()

        XCTAssertTrue(waitForCount(tabRows(in: app), 2, timeout: 5))
        XCTAssertTrue(tabRow(titled: "Basic Configuration", in: app).waitForExistence(timeout: 10))
        // Juste après la page d'origine, qui reste affichée.
        XCTAssertTrue(tabRows(in: app).element(boundBy: 1).label.contains("Basic Configuration"))
        XCTAssertEqual(addressPill(in: app).value as? String, "index.html")
        XCTAssertFalse(peekElement("peekCloseButton", in: app).exists)
    }

    @MainActor
    func testOpenLinkInPeekOpensThePeek() throws {
        let app = try launchOnLocalDocs()
        rightClickWhenSettled(link(containing: "Basic configuration", in: app), in: app)
        menuItem(Self.peekItem, in: app).click()

        XCTAssertTrue(peekElement("peekCloseButton", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: peekElement("peekAddress", in: app), timeout: 10) { $0 == "BASIC_CONFIGURATION_README.html" })
        XCTAssertEqual(tabRows(in: app).count, 1)
        XCTAssertEqual(addressPill(in: app).value as? String, "index.html")
    }

    /// Dans l'aperçu : un onglet en arrière-plan après l'onglet d'origine, et l'aperçu reste ouvert ; pas d'« Ouvrir dans
    /// un aperçu », un lien s'y charge déjà sur place.
    @MainActor
    func testOpenLinkInNewTabFromThePeekKeepsThePeek() throws {
        let app = try launchOnLocalDocs()
        openPeekOnLocalDocs(in: app)
        rightClickWhenSettled(links("main.cf", exact: true, in: app).firstMatch, in: app)
        XCTAssertFalse(menuItem(Self.peekItem, in: app).exists)
        menuItem(Self.newTabItem, in: app).click()

        XCTAssertTrue(waitForCount(tabRows(in: app), 2, timeout: 5))
        XCTAssertTrue(tabRow(titled: "Configuration Parameters", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(peekElement("peekCloseButton", in: app).exists)
        XCTAssertEqual(peekElement("peekAddress", in: app).value as? String, "BASIC_CONFIGURATION_README.html")
        XCTAssertEqual(addressPill(in: app).value as? String, "index.html")
    }

    /// Logo de Postfix, à gauche du titre de la page (texte de remplacement vide : l'image n'est pas exposée).
    @MainActor
    func testOpenImageInNewTabOpensABackgroundTab() throws {
        let app = try launchOnLocalDocs()
        let heading = app.webViews.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Postfix Documentation", "Postfix Documentation"))
            .firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        heading.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: -60, dy: 0)).rightClick()
        let item = menuItem(Self.imageItem, in: app)
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.click()

        XCTAssertTrue(waitForCount(tabRows(in: app), 2, timeout: 5))
        XCTAssertEqual(addressPill(in: app).value as? String, "index.html")
        tabRows(in: app).element(boundBy: 1).click()
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "postfix-logo.jpg" })
    }

    /// Depuis une mini-fenêtre : un onglet en arrière-plan dans la fenêtre principale, comme ⌘-clic ; pas d'aperçu.
    @MainActor
    func testOpenLinkInNewTabFromAMiniWindowAddsATabToTheSidebar() throws {
        try XCTSkipUnless(FileManager.default.isReadableFile(atPath: Self.localDocsPath), "Documentation de Postfix absente")
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        let mini = openMiniWindow(in: app)
        app.typeText("file://\(Self.localDocsPath)\n")
        XCTAssertTrue(waitForValue(of: addressPill(in: mini)) { $0 == "index.html" })

        rightClickWhenSettled(link(containing: "Basic configuration", in: app), in: app)
        XCTAssertFalse(menuItem(Self.peekItem, in: app).exists)
        menuItem(Self.newTabItem, in: app).click()

        XCTAssertTrue(waitForCount(tabRows(in: app), 1, timeout: 5))
        XCTAssertTrue(tabRow(titled: "Basic Configuration", in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(miniWindows(in: app).count, 1)
        XCTAssertEqual(addressPill(in: mini).value as? String, "index.html")
    }

    /// Menu d'une page (hors d'un lien) : Précédent, Suivant, Recharger, Enregistrer sous…, Imprimer…, Afficher le code
    /// source ; ce dernier ouvre le code dans un nouvel onglet au premier plan.
    @MainActor
    func testThePageMenuOpensTheSourceInANewTab() throws {
        let app = try launchOnLocalDocs()
        let page = app.webViews.firstMatch
        let title = page.staticTexts["Postfix Documentation"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        // Sous le titre, à droite du tampon : le fond de la page.
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.06)).rightClick()
        for item in ["Précédent", "Suivant", "Recharger", "Enregistrer sous…", "Imprimer…"] {
            XCTAssertTrue(menuItem(item, in: app).waitForExistence(timeout: 3), item)
        }
        XCTAssertFalse(menuItem("Précédent", in: app).isEnabled)
        menuItem("Afficher le code source", in: app).click()

        XCTAssertTrue(waitForCount(tabRows(in: app), 2, timeout: 5))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0.hasPrefix("matcha-source:") || $0.contains("index.html") })
        let source = app.webViews.firstMatch.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Postfix Documentation'")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10))
    }
}
