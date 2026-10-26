import XCTest

/// Page zoom (task 5.4): ⌘+, ⌘=, ⌘-, ⌘0 and the “115 %” badge next to the address pill (absent at 100 %, a click
/// goes back to 100 %), grayed-out menus, zoom remembered for the site (here local files, which form a single
/// site) on another page and in another tab, Peek, mini window, address bar above the page, “Zoom” row of the site
/// settings (network: example.com). Pages: the stand-in of the Postfix documentation written by the tests
/// (`UITestPages`, no network). These tests move the real mouse.
final class PageZoomUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches the app (with `settings` added) on the home page of the Postfix documentation, alone in the sidebar.
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
        // At 100 %, no badge.
        XCTAssertFalse(zoomBadge(in: app).waitForExistence(timeout: 1))
        XCTAssertTrue(waitForMenuItem("Taille réelle", enabled: false, in: app))
        XCTAssertTrue(waitForMenuItem("Zoom avant", enabled: true, in: app))

        zoom("+", expecting: 115, in: app)
        XCTAssertEqual(zoomBadge(in: app).label, "Zoom de la page")
        // ⌘= is the same as ⌘+, like in Safari.
        zoom("=", expecting: 125, in: app)
        XCTAssertTrue(waitForMenuItem("Taille réelle", enabled: true, in: app))
        zoom("-", expecting: 115, in: app)
        zoom("-", expecting: 100, in: app)
        zoom("-", expecting: 85, in: app)
        zoom("0", expecting: 100, in: app)
        XCTAssertTrue(waitForMenuItem("Taille réelle", enabled: false, in: app))

        // Nothing else opened.
        XCTAssertEqual(tabRows(in: app).count, 1)
        XCTAssertFalse(addressField(in: app).exists)

        // At the end of the list (50 %), “Zoom Out” is grayed out; the badge stays shown.
        for percent in [85, 75, 50] {
            zoom("-", expecting: percent, in: app)
        }
        XCTAssertTrue(waitForMenuItem("Zoom arrière", enabled: false, in: app))
        XCTAssertTrue(waitForPercent(50, of: zoomBadge(in: app), inValue: true))
    }

    /// A click on the badge brings the site back to 100 %, like ⌘0: the badge goes away, the command bar doesn't
    /// open (the badge is next to the pill, not inside it), and another page of the site opens at 100 %.
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

        // Another page of the same site (local files): it opens at 125 %, the badge says so; ⌘+ goes to 150 %.
        clickWhenSettled(link(containing: "Basic configuration", in: app))
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "BASIC_CONFIGURATION_README.html" })
        XCTAssertTrue(waitForPercent(125, of: zoomBadge(in: app), inValue: true))
        zoom("+", expecting: 150, in: app)

        // Another tab of the same site: same zoom.
        openAddress("file://" + UITestPages.path("postconf.5.html"), in: app)
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0 == "postconf.5.html" })
        XCTAssertTrue(waitForPercent(150, of: zoomBadge(in: app), inValue: true))
        zoom("-", expecting: 125, in: app)

        // A page without a site (about:blank) stays at 100 %: no badge.
        openAddress("about:blank?zoom", in: app)
        XCTAssertTrue(waitForValue(of: addressPill(in: app)) { $0.hasPrefix("about:blank") })
        XCTAssertTrue(zoomBadge(in: app).waitForNonExistence(timeout: 3))
        zoom("+", expecting: 115, in: app)
    }

    /// Peek open: ⌘+ zooms its page, shown by the badge in its bar; the page behind, from the same site, follows
    /// (sidebar badge). A click on the Peek's badge brings the site back to 100 % without closing the Peek.
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

    /// Mini window: the badge is in its toolbar; the browser window behind shows none.
    @MainActor
    func testZoomInMiniWindowShowsTheBadgeInItsToolbar() {
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

    /// Address bar above the page: the badge is in the card's bar.
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

    /// “Zoom” row of the site settings: − / % / +, a click on the percentage goes back to 100 %; it follows ⌘+, and
    /// the badge follows the row.
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
        // The keyboard and the row target the same zoom.
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
