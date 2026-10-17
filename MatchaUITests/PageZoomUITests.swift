import XCTest

/// Zoom des pages (tâche 5.4) : ⌘+, ⌘=, ⌘-, ⌘0 et le badge « 115 % » à côté de la pastille d'adresse (absent à 100 %,
/// un clic revient à 100 %), menus grisés, zoom retenu pour le site (ici les fichiers locaux, qui forment un seul site)
/// sur une autre page et dans un autre onglet, aperçu, mini-fenêtre, barre d'adresse au-dessus de la page, ligne
/// « Zoom » des réglages du site (réseau : example.com). Pages : la documentation de Postfix livrée avec macOS (sans
/// réseau ; tests ignorés si elle manque). Ces tests déplacent la vraie souris.
final class PageZoomUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Lance l'app (avec `settings` en plus) sur la page d'accueil de la documentation de Postfix, seule dans la barre.
    @MainActor
    private func launchOnLocalDocs(settings: [String: String] = [:]) throws -> XCUIApplication {
        let app = launchApp(settings: settings)
        XCTAssertTrue(waitForBrowserWindow(of: app))
        try openLocalDocs(in: app)
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "index.html" })
        return app
    }

    @MainActor
    func testKeyboardZoomShowsTheBadgeAndUpdatesTheMenus() throws {
        let app = try launchOnLocalDocs()
        // À 100 %, pas de badge.
        XCTAssertFalse(zoomBadge(in: app).waitForExistence(timeout: 1))
        XCTAssertTrue(waitForMenuItem("Taille réelle", enabled: false, in: app))
        XCTAssertTrue(waitForMenuItem("Zoom avant", enabled: true, in: app))

        zoom("+", expecting: 115, in: app)
        XCTAssertEqual(zoomBadge(in: app).label, "Zoom de la page")
        // ⌘= vaut ⌘+, comme dans Safari.
        zoom("=", expecting: 125, in: app)
        XCTAssertTrue(waitForMenuItem("Taille réelle", enabled: true, in: app))
        zoom("-", expecting: 115, in: app)
        zoom("-", expecting: 100, in: app)
        zoom("-", expecting: 85, in: app)
        zoom("0", expecting: 100, in: app)
        XCTAssertTrue(waitForMenuItem("Taille réelle", enabled: false, in: app))

        // Rien d'autre ne s'est ouvert.
        XCTAssertEqual(tabRows(in: app).count, 1)
        XCTAssertFalse(addressField(in: app).exists)

        // Au bout de la liste (50 %), « Zoom arrière » est grisé ; le badge reste affiché.
        for percent in [85, 75, 50] {
            zoom("-", expecting: percent, in: app)
        }
        XCTAssertTrue(waitForMenuItem("Zoom arrière", enabled: false, in: app))
        XCTAssertTrue(waitForPercent(50, of: zoomBadge(in: app), inValue: true))
    }

    /// Un clic sur le badge ramène le site à 100 %, comme ⌘0 : le badge disparaît, la barre de commande ne s'ouvre pas
    /// (le badge est à côté de la pastille, pas dedans), et une autre page du site s'ouvre à 100 %.
    @MainActor
    func testClickOnTheBadgeResetsTheSite() throws {
        let app = try launchOnLocalDocs()
        zoom("+", expecting: 115, in: app)
        let badge = zoomBadge(in: app)
        clickWhenSettled(badge)
        XCTAssertTrue(badge.waitForNonExistence(timeout: 3))
        XCTAssertFalse(addressField(in: app).waitForExistence(timeout: 1))
        XCTAssertTrue(waitForMenuItem("Taille réelle", enabled: false, in: app))

        clickWhenSettled(link(containing: "Basic configuration", in: app))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "BASIC_CONFIGURATION_README.html" })
        XCTAssertFalse(zoomBadge(in: app).waitForExistence(timeout: 1))
        zoom("+", expecting: 115, in: app)
    }

    @MainActor
    func testZoomIsRememberedForTheSite() throws {
        let app = try launchOnLocalDocs()
        zoom("+", expecting: 115, in: app)
        zoom("+", expecting: 125, in: app)

        // Autre page du même site (fichiers locaux) : elle s'ouvre à 125 %, le badge le dit ; ⌘+ passe à 150 %.
        clickWhenSettled(link(containing: "Basic configuration", in: app))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "BASIC_CONFIGURATION_README.html" })
        XCTAssertTrue(waitForPercent(125, of: zoomBadge(in: app), inValue: true))
        zoom("+", expecting: 150, in: app)

        // Autre onglet du même site : même zoom.
        openAddress("file:///usr/share/doc/postfix/html/postconf.5.html", in: app)
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "postconf.5.html" })
        XCTAssertTrue(waitForPercent(150, of: zoomBadge(in: app), inValue: true))
        zoom("-", expecting: 125, in: app)

        // Une page sans site (about:blank) reste à 100 % : pas de badge.
        openAddress("about:blank?zoom", in: app)
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0.hasPrefix("about:blank") })
        XCTAssertTrue(zoomBadge(in: app).waitForNonExistence(timeout: 3))
        zoom("+", expecting: 115, in: app)
    }

    /// Aperçu ouvert : ⌘+ zoome sa page, montré par le badge de sa barre ; la page derrière, du même site, suit (badge
    /// de la barre latérale). Un clic sur le badge de l'aperçu ramène le site à 100 % sans fermer l'aperçu.
    @MainActor
    func testZoomInPeekShowsTheBadgeInItsToolbar() throws {
        let app = try launchOnLocalDocs()
        openPeekOnLocalDocs(in: app)
        let peek = peekElement("peek", in: app)
        XCTAssertFalse(zoomBadge(in: peek).waitForExistence(timeout: 1))

        zoom("+", expecting: 115, in: app)
        let peekBadge = zoomBadge(in: peek)
        XCTAssertTrue(waitForPercent(115, of: peekBadge, inValue: true))
        XCTAssertTrue(waitForCount(zoomBadges(in: app), 2))

        clickWhenSettled(peekBadge)
        XCTAssertTrue(waitForCount(zoomBadges(in: app), 0))
        XCTAssertTrue(peekElement("peekCloseButton", in: app).exists)

        zoom("+", expecting: 115, in: app)
        peekElement("peekCloseButton", in: app).click()
        XCTAssertTrue(peekElement("peekCloseButton", in: app).waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForPercent(115, of: zoomBadge(in: app), inValue: true))
        zoom("+", expecting: 125, in: app)
    }

    /// Mini-fenêtre : le badge est dans sa barre d'outils ; la fenêtre de navigation derrière n'en montre pas.
    @MainActor
    func testZoomInMiniWindowShowsTheBadgeInItsToolbar() throws {
        try XCTSkipUnless(FileManager.default.isReadableFile(atPath: Self.localDocsPath), "Documentation de Postfix absente")
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        let mini = openMiniWindow(in: app)
        app.typeText("file://\(Self.localDocsPath)\n")
        XCTAssertTrue(addressField(in: mini).waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: addressPill(in: mini)) { $0 == "index.html" })

        app.typeKey("+", modifierFlags: .command)
        XCTAssertTrue(waitForPercent(115, of: zoomBadge(in: mini), inValue: true))
        XCTAssertEqual(zoomBadges(in: browserWindow(in: app)).count, 0)

        clickWhenSettled(zoomBadge(in: mini))
        XCTAssertTrue(zoomBadge(in: mini).waitForNonExistence(timeout: 3))
    }

    /// Barre d'adresse au-dessus de la page : le badge est dans la barre de la carte.
    @MainActor
    func testBadgeInTheTopAddressBar() throws {
        let app = try launchOnLocalDocs(settings: ["addressBarPosition": "top"])
        let pane = pagePanes(in: app).firstMatch
        XCTAssertFalse(zoomBadge(in: pane).waitForExistence(timeout: 1))
        zoom("+", expecting: 115, in: app)
        XCTAssertTrue(waitForPercent(115, of: zoomBadge(in: pane), inValue: true))
        clickWhenSettled(zoomBadge(in: pane))
        XCTAssertTrue(zoomBadge(in: pane).waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testEmptyTabDisablesPageCommands() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openEmptyTab(in: app)
        for title in ["Zoom avant", "Zoom arrière", "Taille réelle", "Imprimer…", "Exporter au format PDF…"] {
            XCTAssertTrue(waitForMenuItem(title, enabled: false, in: app), title)
        }
        app.typeKey("+", modifierFlags: .command)
        XCTAssertFalse(zoomBadge(in: app).waitForExistence(timeout: 1))
    }

    /// Ligne « Zoom » des réglages du site : − / % / +, un clic sur le pourcentage revient à 100 % ; elle suit ⌘+, et le
    /// badge suit la ligne.
    @MainActor
    func testSiteSettingsZoomRow() throws {
        try skipIfOffline()
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openAddress("https://example.com", in: app)
        let button = siteSettingsButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.click()
        XCTAssertTrue(siteSettingsPanel(in: app).waitForExistence(timeout: 3))

        let reset = siteZoomButton("siteZoomResetButton", in: app)
        XCTAssertTrue(reset.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForPercent(100, of: reset, inValue: true))
        XCTAssertFalse(reset.isEnabled)

        siteZoomButton("siteZoomInButton", in: app).click()
        XCTAssertTrue(waitForPercent(115, of: reset, inValue: true))
        XCTAssertTrue(waitForPercent(115, of: zoomBadge(in: app), inValue: true))
        // Le clavier et la ligne visent le même zoom.
        zoom("+", expecting: 125, in: app)
        XCTAssertTrue(waitForPercent(125, of: reset, inValue: true))

        reset.click()
        XCTAssertTrue(waitForPercent(100, of: reset, inValue: true))
        XCTAssertTrue(zoomBadge(in: app).waitForNonExistence(timeout: 3))
        siteZoomButton("siteZoomOutButton", in: app).click()
        XCTAssertTrue(waitForPercent(85, of: reset, inValue: true))
        zoom("0", expecting: 100, in: app)
        XCTAssertTrue(waitForPercent(100, of: reset, inValue: true))
    }
}
