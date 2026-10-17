import XCTest

/// Historique (5.5) : fenêtre ⌘Y, recherche, suppression, effacement, ouverture d'une ligne, fenêtre privée et barre
/// de commande. Pages : la documentation de Postfix livrée avec macOS (sans réseau) ; tests ignorés si elle manque.
/// Ces tests déplacent la vraie souris.
final class HistoryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Lance l'app et visite deux pages de la documentation de Postfix dans un même onglet.
    @MainActor
    private func launchAfterVisitingDocs() throws -> XCUIApplication {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        try visitLocalDocs(in: app)
        return app
    }

    @MainActor
    func testCommandYOpensTheHistoryWindowAndCommandWClosesIt() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        // Rien ne s'ouvre de soi-même au lancement.
        XCTAssertFalse(historyWindow(in: app).exists)

        let window = openHistoryWindow(in: app)
        XCTAssertTrue(historyEmptyState(in: window).waitForExistence(timeout: 5))
        XCTAssertEqual(historyRows(in: window).count, 0)
        // Une seule fenêtre : ⌘Y la ramène devant.
        app.typeKey("y", modifierFlags: .command)
        XCTAssertEqual(app.windows.matching(NSPredicate(format: "title == %@", "Historique")).count, 1)

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(window.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["newTabButton"].exists)
    }

    @MainActor
    func testVisitedPagesAppearAndSearchFiltersThem() throws {
        let app = try launchAfterVisitingDocs()
        let window = openHistoryWindow(in: app)
        XCTAssertTrue(historyRow(titled: "Postfix Basic Configuration", in: window).waitForExistence(timeout: 5))
        XCTAssertTrue(historyRow(titled: "Postfix Documentation", in: window).exists)
        // La plus récente en tête.
        XCTAssertEqual(historyRows(in: window).firstMatch.label, "Postfix Basic Configuration")
        XCTAssertEqual(historyRows(in: window).firstMatch.value as? String, "BASIC_CONFIGURATION_README.html")

        // Recherche sans casse ni accents, sur le titre et l'adresse.
        let search = window.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("BASIC")
        XCTAssertTrue(waitForCount(historyRows(in: window), 1))
        XCTAssertEqual(historyRows(in: window).firstMatch.label, "Postfix Basic Configuration")
        search.typeKey("a", modifierFlags: .command)
        search.typeText("index.html")
        XCTAssertTrue(waitForCount(historyRows(in: window), 1))
        XCTAssertEqual(historyRows(in: window).firstMatch.label, "Postfix Documentation")
        search.typeKey("a", modifierFlags: .command)
        search.typeText("zzqqxx")
        XCTAssertTrue(waitForCount(historyRows(in: window), 0))
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(waitForCount(historyRows(in: window), 2))
    }

    @MainActor
    func testDeleteKeyAndContextMenuRemoveRows() throws {
        let app = try launchAfterVisitingDocs()
        let window = openHistoryWindow(in: app)
        let basic = historyRow(titled: "Postfix Basic Configuration", in: window)
        XCTAssertTrue(basic.waitForExistence(timeout: 5))

        basic.click()
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(basic.waitForNonExistence(timeout: 3))
        XCTAssertEqual(historyRows(in: window).count, 1)

        historyRow(titled: "Postfix Documentation", in: window).rightClick()
        app.menuItems["Supprimer"].click()
        XCTAssertTrue(historyEmptyState(in: window).waitForExistence(timeout: 3))
        // Supprimé de l'historique, pas de la barre latérale.
        XCTAssertEqual(tabRows(in: app).count, 1)
    }

    @MainActor
    func testClearHistoryAsksForAPeriod() throws {
        let app = try launchAfterVisitingDocs()
        let window = openHistoryWindow(in: app)
        XCTAssertTrue(waitForCount(historyRows(in: window), 2, timeout: 5))
        let clear = window.buttons["historyClearButton"]

        // Annuler ne change rien.
        clear.click()
        let cancel = dialogButton("Annuler", in: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        XCTAssertTrue(dialogButton("La dernière heure", in: app).exists)
        XCTAssertTrue(dialogButton("Aujourd'hui et hier", in: app).exists)
        XCTAssertTrue(dialogButton("Tout l'historique", in: app).exists)
        cancel.click()
        XCTAssertEqual(historyRows(in: window).count, 2)

        clear.click()
        let today = dialogButton("Aujourd'hui", in: app)
        XCTAssertTrue(today.waitForExistence(timeout: 3))
        today.click()
        XCTAssertTrue(historyEmptyState(in: window).waitForExistence(timeout: 3))
    }

    @MainActor
    func testDoubleClickOpensTheRowInANewTabOfTheMainWindow() throws {
        let app = try launchAfterVisitingDocs()
        // Plus d'onglet : la page n'est plus que dans l'historique.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(tabRows(in: app), 0))

        let window = openHistoryWindow(in: app)
        let row = historyRow(titled: "Postfix Documentation", in: window)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.doubleClick()
        XCTAssertTrue(waitForCount(tabRows(in: app), 1, timeout: 5))
        XCTAssertTrue(waitForValue(of: addressPill(in: browserWindow(in: app)), timeout: 10) { $0 == "index.html" })
        // La fenêtre principale est passée devant : ⌘T y ouvre la barre de commande.
        openCommandBar(in: app, window: browserWindow(in: app))
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testPrivateWindowRecordsNothing() throws {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        try XCTSkipUnless(FileManager.default.isReadableFile(atPath: Self.localDocsPath), "Documentation de Postfix absente")
        let privateWindow = openPrivateWindow(in: app)
        openCommandBar(in: app, window: privateWindow)
        app.typeText("file://\(Self.localDocsPath)\n")
        XCTAssertTrue(tabRow(titled: "Postfix Documentation", in: app).waitForExistence(timeout: 10))

        // « Afficher tout l'historique » est grisé dans une fenêtre privée.
        app.menuBars.menuBarItems["Historique"].click()
        XCTAssertFalse(app.menuBars.menuItems["Afficher tout l'historique"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(privateWindow.waitForNonExistence(timeout: 5))
        let window = openHistoryWindow(in: app)
        XCTAssertTrue(historyEmptyState(in: window).waitForExistence(timeout: 5))
    }

    @MainActor
    func testCommandBarSuggestsAVisitedPageThatIsNoLongerOpen() throws {
        let app = try launchAfterVisitingDocs()
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(tabRows(in: app), 0))

        openCommandBar(in: app)
        app.typeText("postfix doc")
        let row = commandBarRows(in: app).matching(NSPredicate(format: "label == %@", "Postfix Documentation")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        XCTAssertTrue(waitForCount(tabRows(in: app), 1))
        XCTAssertTrue(waitForValue(of: addressPill(in: app), timeout: 10) { $0 == "index.html" })
    }
}
