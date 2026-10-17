import XCTest

/// Recherche dans la page (5.3) : ⌘F, recherche à la frappe, « Introuvable », ⌘G et ⇧⌘G, ⎋, changement d'onglet,
/// aperçu. Pages : la documentation de Postfix livrée avec macOS (sans réseau ; tests ignorés si elle manque). Ces
/// tests déplacent la vraie souris.
final class FindInPageUITests: XCTestCase {
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
    func testCommandFOpensTheBarAndTypingSearches() throws {
        let app = try launchOnLocalDocs()
        let field = openFindBar(in: app)
        app.typeText("postfix")
        XCTAssertTrue(waitForValue(of: field) { $0 == "postfix" })
        XCTAssertFalse(findStatus(in: app).waitForExistence(timeout: 2), "« postfix » est dans la page")

        replaceFindText(with: "zzqqxx", in: app)
        XCTAssertTrue(waitForNotFound(in: app))

        // Champ vidé : plus de résultat.
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(findStatus(in: app).waitForNonExistence(timeout: 3))

        // ⌘F, barre déjà ouverte : le champ garde le clavier.
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

        // ⌘G rouvre la barre avec le même texte, sans lui donner le clavier ; × la referme.
        app.typeKey("g", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "configuration")
        findButton("findCloseButton", in: app).click()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))

        // La page répond toujours : un lien s'ouvre.
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
        // Onglet vide : rien à chercher, ⌘F n'ouvre rien.
        app.typeKey("f", modifierFlags: .command)
        XCTAssertFalse(field.waitForExistence(timeout: 1))

        // De retour, la barre est là, avec son texte.
        tabRow(titled: "Postfix Documentation", in: app).click()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "postfix")
    }

    /// Aperçu ouvert : ⌘F cherche dans sa page ; ⎋ ferme la barre, pas l'aperçu, puis un second ⎋ ferme l'aperçu.
    @MainActor
    func testFindInPeekAndEscapeClosesOnlyTheBar() throws {
        let app = try launchOnLocalDocs()
        openPeekOnLocalDocs(in: app)
        let field = openFindBar(in: app)
        // Dans le panneau de l'aperçu, sous sa barre.
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
