import XCTest

/// Screenshots of the window for visual checks, attached to the test results.
/// Skipped unless `MATCHA_SCREENSHOT` is set:
///
///     TEST_RUNNER_MATCHA_SCREENSHOT=1 xcodebuild … test -only-testing:MatchaUITests/ScreenshotUITests
///     xcrun xcresulttool export attachments --path <result>.xcresult --output-path <folder>
///
/// Optional variables:
/// - `MATCHA_SCREENSHOT_URLS`: comma-separated addresses, each opened in a tab;
/// - `MATCHA_SCREENSHOT_MENU`: context menu actions, “Item@tab title” separated by `;`
///   (e.g. “Ajouter aux favoris@Apple;Épingler@GitHub”);
/// - `MATCHA_SCREENSHOT_PEEK`: also captures the hidden sidebar (⌘S), then revealed by hovering the left edge
///   (hidden sidebar, nothing to do with link Peek);
/// - `MATCHA_SCREENSHOT_PEEK_LINK`: text of a link of the last page of `MATCHA_SCREENSHOT_URLS`, opened with
///   Shift-click in Peek (`18-apercu`), then “Open as Tab” (`19-apercu-onglet`). Local pages without
///   network: `MATCHA_SCREENSHOT_URLS=file:///usr/share/doc/postfix/html/index.html` and
///   `MATCHA_SCREENSHOT_PEEK_LINK="Basic configuration"`;
/// - `MATCHA_SCREENSHOT_SETTINGS`: also captures each tab of the settings (⌘,);
/// - `MATCHA_SCREENSHOT_SETTINGS_VALUES`: settings forced at launch (“addressBarPosition=top,…”);
/// - `MATCHA_SCREENSHOT_THEME`: opens the theme editor and picks this preset theme (“Océan”…);
/// - `MATCHA_SCREENSHOT_SPACES`: creates this number of Spaces with the + button;
/// - `MATCHA_SCREENSHOT_COMMAND_BAR`: text typed in the command bar (⌘T), captured with its
///   results, then with the selection moved down, then the edit bar (⌘L). To see the search engine
///   suggestions: `MATCHA_SCREENSHOT_SETTINGS_VALUES=showsSearchSuggestions=YES`; in dark mode:
///   `MATCHA_SCREENSHOT_SETTINGS_VALUES=AppleInterfaceStyle=Dark`; in light mode on a Mac set to
///   dark: `NSRequiresAquaSystemAppearance=YES` (`AppleInterfaceStyle=Light` stays dark);
/// - `MATCHA_SCREENSHOT_PRIVATE`: also captures the command bar (⌘T) of a new private window
///   (⇧⌘N), with the text of `MATCHA_SCREENSHOT_COMMAND_BAR` if it is set;
/// - `MATCHA_SCREENSHOT_COPY_URL`: also captures the “URL Copied” confirmation after ⇧⌘C, on the displayed
///   tab (without `MATCHA_SCREENSHOT_URLS`, an `about:blank?copy` tab is opened first);
/// - `MATCHA_SCREENSHOT_SPLIT`: number of panes (2 to 4). Without `MATCHA_SCREENSHOT_URLS`, first opens
///   `about:blank?split1`…; then “Open in Split View” on the first unselected tab row until this
///   number; captures `15-split`, clicks the left pane (`16-split-panneau-actif`), hovers the first
///   divider (`17-split-separateur`). With `…_SETTINGS_VALUES=addressBarPosition=top`: one bar per pane;
/// - `MATCHA_SCREENSHOT_MINI`: text typed in a mini window opened from the File menu, after the other
///   screenshots: `20-mini-vide` (bar open), `21-mini-page` (after Return), `22-mini-flottante` (whole screen,
///   browser window active: the mini window stays in front), `23-mini-remise` (⌘O, the page in the Space).
///   Without network: `MATCHA_SCREENSHOT_MINI=about:blank?mini`;
/// - `MATCHA_SCREENSHOT_DOWNLOADS`: path of a local file that WebKit doesn't display (“1”: the one of the
///   downloads tests), downloaded to ~/Downloads/MatchaUITests, deleted at the end: `36-telechargements-vide`
///   (empty panel, before the download), `24-telechargement-bouton` (button in the sidebar footer),
///   `25-telechargements-liste` (open list);
/// - `MATCHA_SCREENSHOT_SITE_SETTINGS`: site settings panel of the displayed tab (`26-reglages-site`), then the
///   confirmation of clearing its data (`27-reglages-site-effacer`); without `MATCHA_SCREENSHOT_URLS`, opens
///   https://example.com (network). With `…_SETTINGS_VALUES=addressBarPosition=top`: at the top of the card;
/// - `MATCHA_SCREENSHOT_PERMISSION_URL`: page that requests the camera or the microphone, and
///   `MATCHA_SCREENSHOT_PERMISSION_BUTTON` (optional): text of the page button to click to start the request;
///   captures the banner (`28-permission-bandeau`). Network needed; the macOS access request may appear the
///   first time;
/// - `MATCHA_SCREENSHOT_FIND`: text searched (⌘F) in the displayed tab: `29-recherche-trouvee`, then “zzqqxx”:
///   `30-recherche-introuvable`. Without `MATCHA_SCREENSHOT_URLS`, opens the Postfix documentation (no network):
///   `MATCHA_SCREENSHOT_FIND=postfix`;
/// - `MATCHA_SCREENSHOT_ZOOM`: zoom badge next to the address pill after ⌘+ (`31-zoom-badge`); with
///   `=site`, the “Zoom” row of the site settings of example.com (`32-zoom-reglages-site`, network). See
///   `ScreenshotUITests+Zoom`;
/// - `MATCHA_SCREENSHOT_HISTORY`: history window (⌘Y) after visiting two pages of the Postfix documentation
///   (no network; those of `MATCHA_SCREENSHOT_URLS` if set): `33-historique`; with a text (not “1”), this text
///   searched: `34-historique-recherche`; then the “Clear History…” dialog: `35-historique-effacer`.
///   E.g. `MATCHA_SCREENSHOT_HISTORY=basic`. See `ScreenshotUITests+History`;
/// - `MATCHA_SCREENSHOT_FOLDER`: customized pinned folder, named after the value (“Projets” for “1”), and its
///   subfolder “Client” (no network): “Customize…” panel open below the subfolder
///   (`37-dossier-panneau`), then both rows, panel closed (`38-dossier-personnalise`). In dark mode:
///   `MATCHA_SCREENSHOT_SETTINGS_VALUES=AppleInterfaceStyle=Dark`. See `ScreenshotUITests+Folders`;
/// - `MATCHA_SCREENSHOT_ARC`: import of an Arc sidebar from the File menu (“1”: the made-up example of the unit
///   tests): picker, preview, imported Spaces. See `ScreenshotUITests+ArcImport`.
///
/// The `1-vide` screenshot shows the window without a tab: the empty page suggests ⌘T, the command bar
/// never opens by itself.
final class ScreenshotUITests: XCTestCase {
    private let environment = ProcessInfo.processInfo.environment

    @MainActor
    func testCaptureWindow() throws {
        guard environment["MATCHA_SCREENSHOT"] != nil else {
            throw XCTSkip("MATCHA_SCREENSHOT non défini")
        }
        let app = launchApp(settings: settingsOverrides)
        let window = app.windows.firstMatch
        XCTAssertTrue(waitForBrowserWindow(of: app))
        attach(window.screenshot(), as: "1-vide")

        openAddresses(in: app, window: window)
        applyMenuActions(in: app, window: window)
        if environment["MATCHA_SCREENSHOT_COPY_URL"] != nil {
            captureCopyConfirmation(in: app, window: window)
        }
        if let count = environment["MATCHA_SCREENSHOT_SPLIT"].flatMap(Int.init) {
            captureSplit(panes: min(max(count, 2), 4), in: app, window: window)
        }
        if let query = environment["MATCHA_SCREENSHOT_COMMAND_BAR"] {
            captureCommandBar(typing: query, in: app, window: window)
        }
        if environment["MATCHA_SCREENSHOT_PRIVATE"] != nil {
            capturePrivateCommandBar(typing: environment["MATCHA_SCREENSHOT_COMMAND_BAR"], in: app)
        }
        if let text = environment["MATCHA_SCREENSHOT_PEEK_LINK"] {
            capturePeek(link: text, in: app, window: window)
        }
        // After Peek (its page must stay displayed), before the hidden sidebar (the button must be visible).
        try captureDownloads(in: app, window: window)
        captureSiteSettings(in: app, window: window)
        capturePermissionBanner(in: app, window: window)
        try captureFindBar(in: app, window: window)
        try captureZoom(in: app, window: window)
        try captureHistory(in: app)
        captureFolderCustomization(in: app, window: window)
        captureArcImport(in: app, window: window)
        if environment["MATCHA_SCREENSHOT_PEEK"] != nil {
            captureHiddenSidebar(in: app, window: window)
        }
        captureSpaces(in: app, window: window)
        if let preset = environment["MATCHA_SCREENSHOT_THEME"] {
            captureThemeEditor(choosing: preset, in: app, window: window)
        }
        if environment["MATCHA_SCREENSHOT_SETTINGS"] != nil {
            captureSettings(in: app)
        }
        if let text = environment["MATCHA_SCREENSHOT_MINI"] {
            captureMiniWindow(typing: text, in: app)
        }
    }

    /// `MATCHA_SCREENSHOT_SPACES` Spaces created with the + button.
    @MainActor
    private func captureSpaces(in app: XCUIApplication, window: XCUIElement) {
        guard let count = environment["MATCHA_SCREENSHOT_SPACES"].flatMap(Int.init), count > 0 else {
            return
        }
        for _ in 0 ..< count {
            createSpace(in: app)
            sleep(1)
        }
        attach(window.screenshot(), as: "9-spaces")
    }

    @MainActor
    private func captureThemeEditor(choosing preset: String, in app: XCUIApplication, window: XCUIElement) {
        app.buttons["spaceButton"].click()
        sleep(1)
        attach(window.screenshot(), as: "7-theme-editeur")
        app.buttons[preset].click()
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).click()
        sleep(1)
        attach(window.screenshot(), as: "8-theme-\(preset)")
    }

    /// Settings forced for the screenshot: `MATCHA_SCREENSHOT_SETTINGS_VALUES`, comma-separated “key=value” pairs;
    /// with `MATCHA_SCREENSHOT_DOWNLOADS`, the test downloads folder.
    private var settingsOverrides: [String: String] {
        let pairs = environment["MATCHA_SCREENSHOT_SETTINGS_VALUES"]?.split(separator: ",") ?? []
        let settings = Dictionary(pairs.compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }) { _, last in last }
        guard environment["MATCHA_SCREENSHOT_DOWNLOADS"] != nil else {
            return settings
        }
        return settings.merging(Self.downloadsTestSettings) { _, test in test }
    }

    @MainActor
    private func openAddresses(in app: XCUIApplication, window: XCUIElement) {
        let addresses = environment["MATCHA_SCREENSHOT_URLS"]?.split(separator: ",").map(String.init) ?? []
        guard !addresses.isEmpty else {
            return
        }
        for address in addresses {
            openAddress(address, in: app)
            sleep(4)
        }
        attach(window.screenshot(), as: "2-onglets")
    }

    @MainActor
    private func applyMenuActions(in app: XCUIApplication, window: XCUIElement) {
        let actions = environment["MATCHA_SCREENSHOT_MENU"]?.split(separator: ";").map(String.init) ?? []
        guard !actions.isEmpty else {
            return
        }
        for action in actions {
            let parts = action.split(separator: "@", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }
            let row = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", parts[1]))
                .matching(NSPredicate(format: "identifier IN %@", ["tabRow", "favoriteTile"]))
                .firstMatch
            row.rightClick()
            app.menuItems[parts[0]].click()
        }
        attach(window.screenshot(), as: "3-rangement")
    }

    /// Split of `count` panes formed from the menu, then the left pane made active, then the handle
    /// hovered.
    @MainActor
    private func captureSplit(panes count: Int, in app: XCUIApplication, window: XCUIElement) {
        if environment["MATCHA_SCREENSHOT_URLS"] == nil {
            for index in 1 ... count {
                openAddress("about:blank?split\(index)", in: app)
            }
        }
        // At most one try per pane: a menu that adds nothing doesn't block the screenshot.
        for _ in 0 ..< count where pagePanes(in: app).count < count {
            guard let row = tabRows(in: app).allElementsBoundByIndex.first(where: { !$0.isSelected }) else {
                break
            }
            row.rightClick()
            app.menuItems["Ouvrir en split"].click()
            sleep(1)
        }
        sleep(1)
        attach(window.screenshot(), as: "15-split")
        orderedPagePanes(in: app).first?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        sleep(1)
        attach(window.screenshot(), as: "16-split-panneau-actif")
        splitDivider(in: app).hover()
        sleep(1)
        attach(window.screenshot(), as: "17-split-separateur")
    }

    /// Command bar with its results, then the 2nd row selected, then editing of the displayed tab.
    @MainActor
    private func captureCommandBar(typing query: String, in app: XCUIApplication, window: XCUIElement) {
        openCommandBar(in: app)
        app.typeText(query)
        sleep(2)
        attach(window.screenshot(), as: "10-barre-commande")
        app.typeKey(.downArrow, modifierFlags: [])
        sleep(1)
        attach(window.screenshot(), as: "11-barre-commande-selection")
        app.typeKey(.escape, modifierFlags: [])
        guard tabRows(in: app).count > 0 else {
            return
        }
        openCommandBar(in: app, newTab: false)
        sleep(1)
        attach(window.screenshot(), as: "12-barre-commande-edition")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Command bar (⌘T) of a new private window, always dark.
    @MainActor
    private func capturePrivateCommandBar(typing query: String?, in app: XCUIApplication) {
        let privateWindow = openPrivateWindow(in: app)
        openCommandBar(in: app, window: privateWindow)
        if let query {
            app.typeText(query)
        }
        sleep(2)
        attach(privateWindow.screenshot(), as: "13-barre-commande-privee")
        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(privateWindow.waitForNonExistence(timeout: 5))
    }

    /// Peek opened by Shift-click on the link `text`, then turned into a tab.
    @MainActor
    private func capturePeek(link text: String, in app: XCUIApplication, window: XCUIElement) {
        let source = link(containing: text, in: app)
        guard source.exists else {
            XCTFail("Lien « \(text) » introuvable")
            return
        }
        shiftClick(source)
        sleep(2)
        attach(window.screenshot(), as: "18-apercu")
        peekElement("peekOpenAsTabButton", in: app).click()
        sleep(1)
        attach(window.screenshot(), as: "19-apercu-onglet")
    }

    @MainActor
    private func captureHiddenSidebar(in app: XCUIApplication, window: XCUIElement) {
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).hover()
        app.typeKey("s", modifierFlags: [.command, .control])
        sleep(1)
        attach(window.screenshot(), as: "4-barre-masquee")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 3, dy: 0)).hover()
        sleep(1)
        attach(window.screenshot(), as: "5-barre-survolee")
    }

    @MainActor
    private func captureSettings(in app: XCUIApplication) {
        app.typeKey(",", modifierFlags: .command)
        sleep(1)
        let settings = app.windows.element(boundBy: 0)
        for (index, tab) in ["Général", "Apparence", "Profils", "Confidentialité", "Extensions"].enumerated() {
            app.toolbars.buttons[tab].click()
            sleep(1)
            attach(settings.screenshot(), as: "6-reglages-\(index)")
        }
    }

    func attach(_ screenshot: XCUIScreenshot, as name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
