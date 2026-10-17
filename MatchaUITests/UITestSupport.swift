import AppKit
import XCTest

/// Outils partagés des tests d'interface. Tout est synchrone : les appels à XCUIApplication depuis
/// du code asynchrone peuvent bloquer.
extension XCTestCase {
    /// Attend que la valeur de `element` vérifie `condition`.
    @MainActor
    func waitForValue(of element: XCUIElement, timeout: TimeInterval = 20, _ condition: @escaping (String) -> Bool) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let value = (object as? XCUIElement)?.value as? String else {
                return false
            }
            return condition(value)
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    /// Attend que `query` compte `expected` éléments : les changements animés ne sont pas instantanés.
    @MainActor
    func waitForCount(_ query: XCUIElementQuery, _ expected: Int, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "count == %d", expected)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: query)], timeout: timeout) == .completed
    }

    /// Clique `element` une fois sa position stable : juste après un glisser-déposer ou une ouverture animée,
    /// la vue bouge encore et un clic immédiat viserait l'ancienne place de l'élément.
    @MainActor
    func clickWhenSettled(_ element: XCUIElement, timeout: TimeInterval = 3) {
        var previous = element.frame
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            let current = element.frame
            if current == previous {
                break
            }
            previous = current
        }
        // Au centre, par coordonnées : un lien de page est entièrement couvert par son texte, et XCTest refuse
        // alors de cliquer l'élément lui-même.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    /// Place le pointeur au milieu de la page, loin du bord qui fait apparaître la barre masquée.
    @MainActor
    func moveAwayFromLeftEdge(in window: XCUIElement) {
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).hover()
    }

    @MainActor
    func waitForKeyboardFocus(of element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate { object, _ in
            ((object as? XCUIElement)?.value(forKey: "hasKeyboardFocus") as? Bool) == true
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    /// Fait glisser `element` horizontalement depuis son centre.
    @MainActor
    func drag(_ element: XCUIElement, by distance: CGFloat) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: distance, dy: 0)))
    }

    /// Réglages imposés à chaque lancement : les valeurs par défaut de l'app (les réglages réels de
    /// l'utilisateur ne doivent pas changer le résultat des tests), sans alerte avant de quitter (elle
    /// bloquerait les relances). La largeur de la barre latérale n'est pas imposée : le test de
    /// redimensionnement doit pouvoir la modifier.
    static let defaultSettings = [
        "ApplePersistenceIgnoreState": "YES",
        // Base en mémoire : les tests ne lisent ni ne modifient les onglets de l'utilisateur.
        "inMemoryStore": "YES",
        "confirmBeforeQuitting": "NO",
        "searchEngine": "google",
        "appearance": "system",
        "homePage": "",
        "newTabPage": "blank",
        "showsHomeButton": "NO",
        "addressBarPosition": "sidebar",
        "showsNavigationButtons": "YES",
        // Jamais de requête au moteur de recherche pendant les tests.
        "showsSearchSuggestions": "NO",
        // Les liens des favoris et des épinglés restent dans leur onglet (valeur par défaut de l'app).
        "opensPinnedLinksInPeek": "NO",
        // Pas de raccourci global pour la mini-fenêtre (texte « NO » : aucun raccourci, rien n'est écrit) : ⌥⌘N
        // reste à la Matcha de l'utilisateur. Le test du raccourci en impose un autre.
        "KeyboardShortcuts_openMiniWindow": "NO",
    ]

    /// Langue imposée à chaque lancement : les tests cherchent les éléments par leurs textes français,
    /// quelle que soit la langue du Mac.
    static let languageArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]

    /// Fenêtre de navigation imposée à chaque lancement : 1400 × 900 pt en haut à gauche de l'écran principal.
    /// La position retenue par l'app (« NSWindow Frame browser », peut-être sur un autre écran, éteint ou
    /// occupé) ne joue plus sur les tests ; celle de l'utilisateur n'est pas modifiée.
    @MainActor
    static var windowFrameArguments: [String] {
        guard let screen = NSScreen.screens.first?.visibleFrame else {
            return []
        }
        let width = min(1400, screen.width - 80)
        let height = min(900, screen.height - 80)
        let frame = [screen.minX + 40, screen.maxY - 40 - height, width, height]
        let values = (frame + [screen.minX, screen.minY, screen.width, screen.height]).map { String(Int($0)) }
        return ["-NSWindow Frame browser", values.joined(separator: " ")]
    }

    /// Lance l'app en français, sans restaurer les fenêtres d'un lancement précédent, avec les réglages
    /// par défaut et `settings` en plus, pour ce lancement seulement (« -clé valeur »), sans toucher à
    /// ceux de l'utilisateur. La fenêtre s'ouvre sur l'écran principal.
    @MainActor
    func launchApp(settings: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += Self.languageArguments + Self.windowFrameArguments
        var values = Self.defaultSettings
        values.merge(settings) { _, new in new }
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            app.launchArguments += ["-\(key)", value]
        }
        app.launch()
        return app
    }

    /// Fenêtre de navigation prête : son bouton « Nouvel onglet » est affiché. La barre de commande ne
    /// s'ouvre jamais d'elle-même, au lancement comme dans une nouvelle fenêtre.
    @MainActor
    func waitForBrowserWindow(of app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        app.buttons["newTabButton"].waitForExistence(timeout: timeout)
    }

    /// Nouvelle fenêtre privée (⇧⌘N), sans barre de commande. Aucun clic ensuite : le raccourci
    /// suivant (⌘T) doit l'atteindre aussitôt, comme pour l'utilisateur.
    @MainActor
    func openPrivateWindow(in app: XCUIApplication) -> XCUIElement {
        app.typeKey("n", modifierFlags: [.command, .shift])
        let window = app.windows.matching(NSPredicate(format: "title == %@", "Navigation privée")).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        // La barre ne s'ouvre jamais d'elle-même (vérifié avant tout clic, qui la fermerait).
        XCTAssertFalse(addressField(in: window).waitForExistence(timeout: 1))
        return window
    }

    /// Champ de la barre de commande ; `scope` : l'app, ou une fenêtre précise (fenêtre privée).
    @MainActor
    func addressField(in scope: XCUIElement) -> XCUIElement {
        scope.textFields["addressField"]
    }

    /// Pastille d'adresse (bouton) : sa valeur est le domaine affiché.
    @MainActor
    func addressPill(in scope: XCUIElement) -> XCUIElement {
        scope.descendants(matching: .any).matching(identifier: "addressPill").firstMatch
    }

    @MainActor
    func commandBarRows(in scope: XCUIElement) -> XCUIElementQuery {
        scope.descendants(matching: .any).matching(identifier: "commandBarRow")
    }

    /// ⌘T (nouvel onglet) ou ⌘L (onglet affiché) : la barre de commande s'ouvre et son champ prend le
    /// clavier. `window` : la fenêtre où elle doit s'ouvrir (fenêtre privée).
    @MainActor
    @discardableResult
    func openCommandBar(in app: XCUIApplication, window: XCUIElement? = nil, newTab: Bool = true) -> XCUIElement {
        app.typeKey(newTab ? "t" : "l", modifierFlags: .command)
        let field = addressField(in: window ?? app)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        return field
    }

    /// ⌘T puis Entrée sans texte : un onglet vide, comme l'ancien ⌘T. `window` : la fenêtre visée
    /// (fenêtre privée).
    @MainActor
    func openEmptyTab(in app: XCUIApplication, window: XCUIElement? = nil) {
        let field = openCommandBar(in: app, window: window)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }

    /// ⌘T (nouvel onglet) ou ⌘L (onglet affiché), puis `text` et Entrée.
    @MainActor
    func openAddress(_ text: String, in app: XCUIApplication, newTab: Bool = true) {
        let field = openCommandBar(in: app, newTab: newTab)
        app.typeText("\(text)\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func tabRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "tabRow")
    }

    /// Ligne d'onglet dont le titre contient `title`.
    @MainActor
    func tabRow(titled title: String, in app: XCUIApplication) -> XCUIElement {
        tabRows(in: app).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    // MARK: Split view

    /// Cartes des panneaux affichés (une seule hors split, même sans onglet).
    @MainActor
    func pagePanes(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "pagePane")
    }

    /// Cartes des panneaux de gauche à droite.
    @MainActor
    func orderedPagePanes(in app: XCUIApplication) -> [XCUIElement] {
        pagePanes(in: app).allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
    }

    @MainActor
    func splitRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "splitRow")
    }

    @MainActor
    func splitSegments(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "splitSegment")
    }

    /// Morceau de la ligne d'un split dont le titre contient `title`.
    @MainActor
    func splitSegment(titled title: String, in app: XCUIApplication) -> XCUIElement {
        splitSegments(in: app).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// Poignée entre les deux premiers panneaux.
    @MainActor
    func splitDivider(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "splitDivider").firstMatch
    }

    /// « Ouvrir en split » dans le menu de la ligne d'onglet `title`.
    @MainActor
    func openInSplit(_ title: String, in app: XCUIApplication) {
        tabRow(titled: title, in: app).rightClick()
        app.menuItems["Ouvrir en split"].click()
    }

    /// Glisse la ligne d'onglet `title` jusqu'à `target`, lentement, avec une pause à l'arrivée : la zone de
    /// dépôt de la carte a le temps de choisir son bord.
    @MainActor
    func dragTab(titled title: String, to target: XCUICoordinate, in app: XCUIApplication) {
        tabRow(titled: title, in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    /// Les tests qui chargent une vraie page sont ignorés sans accès à Internet.
    func skipIfOffline() throws {
        let reachable = expectation(description: "example.com répond")
        var request = URLRequest(url: URL(string: "https://example.com/")!)
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if data != nil {
                reachable.fulfill()
            }
        }.resume()
        let online = XCTWaiter().wait(for: [reachable], timeout: 6) == .completed
        try XCTSkipUnless(online, "Pas d'accès à example.com")
    }
}
