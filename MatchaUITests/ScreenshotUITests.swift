import XCTest

/// Captures de la fenêtre pour le contrôle visuel, jointes au résultat des tests.
/// Ignoré sauf si `MATCHA_SCREENSHOT` est défini :
///
///     TEST_RUNNER_MATCHA_SCREENSHOT=1 xcodebuild … test -only-testing:MatchaUITests/ScreenshotUITests
///     xcrun xcresulttool export attachments --path <résultat>.xcresult --output-path <dossier>
///
/// Variables facultatives :
/// - `MATCHA_SCREENSHOT_URLS` : adresses séparées par des virgules, ouvertes chacune dans un onglet ;
/// - `MATCHA_SCREENSHOT_MENU` : actions du menu contextuel, « Élément@titre d'onglet » séparées par des `;`
///   (ex. « Ajouter aux favoris@Apple;Épingler@GitHub ») ;
/// - `MATCHA_SCREENSHOT_PEEK` : capture aussi la barre masquée (⌘S), puis apparue au survol du bord gauche
///   (barre latérale masquée, rien à voir avec l'aperçu des liens) ;
/// - `MATCHA_SCREENSHOT_PEEK_LINK` : texte d'un lien de la dernière page de `MATCHA_SCREENSHOT_URLS`, ouvert par
///   Maj+clic dans l'aperçu (`18-apercu`), puis « Ouvrir en onglet » (`19-apercu-onglet`). Pages locales sans
///   réseau : `MATCHA_SCREENSHOT_URLS=file:///usr/share/doc/postfix/html/index.html` et
///   `MATCHA_SCREENSHOT_PEEK_LINK="Basic configuration"` ;
/// - `MATCHA_SCREENSHOT_SETTINGS` : capture aussi chaque onglet des réglages (⌘,) ;
/// - `MATCHA_SCREENSHOT_SETTINGS_VALUES` : réglages imposés au lancement (« addressBarPosition=top,… ») ;
/// - `MATCHA_SCREENSHOT_THEME` : ouvre l'éditeur de thème et choisit ce thème prédéfini (« Océan »…) ;
/// - `MATCHA_SCREENSHOT_SPACES` : crée ce nombre de Spaces avec le bouton + ;
/// - `MATCHA_SCREENSHOT_COMMAND_BAR` : texte tapé dans la barre de commande (⌘T), capturée avec ses
///   résultats, puis la sélection descendue, puis la barre d'édition (⌘L). Pour voir les suggestions du
///   moteur : `MATCHA_SCREENSHOT_SETTINGS_VALUES=showsSearchSuggestions=YES` ; en sombre :
///   `MATCHA_SCREENSHOT_SETTINGS_VALUES=AppleInterfaceStyle=Dark` ; en clair sur un Mac réglé en
///   sombre : `NSRequiresAquaSystemAppearance=YES` (`AppleInterfaceStyle=Light` reste sombre) ;
/// - `MATCHA_SCREENSHOT_PRIVATE` : capture aussi la barre de commande (⌘T) d'une nouvelle fenêtre privée
///   (⇧⌘N), avec le texte de `MATCHA_SCREENSHOT_COMMAND_BAR` s'il est défini ;
/// - `MATCHA_SCREENSHOT_COPY_URL` : capture aussi la confirmation « URL copiée » après ⇧⌘C, sur l'onglet
///   affiché (sans `MATCHA_SCREENSHOT_URLS`, un onglet `about:blank?copy` est ouvert d'abord) ;
/// - `MATCHA_SCREENSHOT_SPLIT` : nombre de panneaux (2 à 4). Sans `MATCHA_SCREENSHOT_URLS`, ouvre d'abord
///   `about:blank?split1`… ; puis « Ouvrir en split » sur la première ligne d'onglet non sélectionnée jusqu'à ce
///   nombre ; capture `15-split`, clique le panneau de gauche (`16-split-panneau-actif`), survole le premier
///   séparateur (`17-split-separateur`). Avec `…_SETTINGS_VALUES=addressBarPosition=top` : une barre par panneau ;
/// - `MATCHA_SCREENSHOT_MINI` : texte tapé dans une mini-fenêtre ouverte par le menu Fichier, après les autres
///   captures : `20-mini-vide` (barre ouverte), `21-mini-page` (après Entrée), `22-mini-flottante` (écran entier,
///   fenêtre du navigateur active : la mini-fenêtre reste devant), `23-mini-remise` (⌘O, la page dans le Space).
///   Sans réseau : `MATCHA_SCREENSHOT_MINI=about:blank?mini` ;
/// - `MATCHA_SCREENSHOT_DOWNLOADS` : chemin d'un fichier local que WebKit n'affiche pas (« 1 » : celui des tests
///   des téléchargements), téléchargé dans ~/Downloads/MatchaUITests, effacé à la fin : `24-telechargement-bouton`
///   (bouton du pied de la barre), `25-telechargements-liste` (liste ouverte) ;
/// - `MATCHA_SCREENSHOT_SITE_SETTINGS` : panneau des réglages du site de l'onglet affiché (`26-reglages-site`), puis la
///   confirmation de l'effacement de ses données (`27-reglages-site-effacer`) ; sans `MATCHA_SCREENSHOT_URLS`, ouvre
///   https://example.com (réseau). Avec `…_SETTINGS_VALUES=addressBarPosition=top` : en haut de la carte ;
/// - `MATCHA_SCREENSHOT_PERMISSION_URL` : page qui demande la caméra ou le micro, et `MATCHA_SCREENSHOT_PERMISSION_BUTTON`
///   (facultatif) : texte du bouton de la page à cliquer pour lancer la demande ; capture le bandeau
///   (`28-permission-bandeau`). Réseau nécessaire ; la demande d'accès de macOS peut apparaître la première fois ;
/// - `MATCHA_SCREENSHOT_FIND` : texte cherché (⌘F) dans l'onglet affiché : `29-recherche-trouvee`, puis « zzqqxx » :
///   `30-recherche-introuvable`. Sans `MATCHA_SCREENSHOT_URLS`, ouvre la documentation de Postfix (sans réseau) :
///   `MATCHA_SCREENSHOT_FIND=postfix` ;
/// - `MATCHA_SCREENSHOT_ZOOM` : badge du zoom à côté de la pastille d'adresse après ⌘+ (`31-zoom-badge`) ; avec
///   `=site`, la ligne « Zoom » des réglages du site d'example.com (`32-zoom-reglages-site`, réseau). Voir
///   `ScreenshotUITests+Zoom` ;
/// - `MATCHA_SCREENSHOT_HISTORY` : fenêtre de l'historique (⌘Y) après la visite de deux pages de la documentation de
///   Postfix (sans réseau ; celles de `MATCHA_SCREENSHOT_URLS` si défini) : `33-historique` ; avec un texte (pas « 1 »),
///   ce texte cherché : `34-historique-recherche` ; puis le dialogue « Effacer l'historique… » : `35-historique-effacer`.
///   Ex. `MATCHA_SCREENSHOT_HISTORY=basic`. Voir `ScreenshotUITests+History`.
///
/// La capture `1-vide` montre la fenêtre sans onglet : la page vide invite à ⌘T, la barre de commande
/// ne s'ouvre jamais d'elle-même.
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
        // Après l'aperçu (sa page doit rester affichée), avant la barre masquée (le bouton doit être visible).
        try captureDownloads(in: app, window: window)
        captureSiteSettings(in: app, window: window)
        capturePermissionBanner(in: app, window: window)
        try captureFindBar(in: app, window: window)
        try captureZoom(in: app, window: window)
        try captureHistory(in: app)
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

    /// `MATCHA_SCREENSHOT_SPACES` Spaces créés avec le bouton +.
    @MainActor
    private func captureSpaces(in app: XCUIApplication, window: XCUIElement) {
        guard let count = environment["MATCHA_SCREENSHOT_SPACES"].flatMap(Int.init), count > 0 else {
            return
        }
        for _ in 0 ..< count {
            app.buttons["newSpaceButton"].click()
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

    /// Réglages imposés pour la capture : `MATCHA_SCREENSHOT_SETTINGS_VALUES`, « clé=valeur » séparés par des virgules ;
    /// avec `MATCHA_SCREENSHOT_DOWNLOADS`, le dossier des téléchargements de test.
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

    /// Split de `count` panneaux formé par le menu, puis le panneau de gauche rendu actif, puis la poignée
    /// survolée.
    @MainActor
    private func captureSplit(panes count: Int, in app: XCUIApplication, window: XCUIElement) {
        if environment["MATCHA_SCREENSHOT_URLS"] == nil {
            for index in 1 ... count {
                openAddress("about:blank?split\(index)", in: app)
            }
        }
        // Un essai par panneau au plus : un menu qui n'ajoute rien ne bloque pas la capture.
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

    /// Barre de commande avec ses résultats, puis la 2e ligne sélectionnée, puis l'édition de l'onglet affiché.
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

    /// Barre de commande (⌘T) d'une nouvelle fenêtre privée, toujours sombre.
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

    /// Aperçu ouvert par Maj+clic sur le lien `text`, puis passé en onglet.
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
        app.typeKey("s", modifierFlags: .command)
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
        for (index, tab) in ["Général", "Apparence", "Profils", "Confidentialité"].enumerated() {
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
