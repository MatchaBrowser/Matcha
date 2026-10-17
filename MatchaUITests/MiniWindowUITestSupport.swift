import XCTest

/// Outils des tests de la mini-fenêtre. Les recherches visent toujours une fenêtre précise : la fenêtre de
/// navigation et la mini-fenêtre ont chacune leur pastille d'adresse.
extension XCTestCase {
    /// Valeur de lancement d'un raccourci de KeyboardShortcuts (« -KeyboardShortcuts_openMiniWindow <valeur> »).
    /// Les guillemets extérieurs sont indispensables : `UserDefaults` lit alors un texte (le JSON du raccourci) ;
    /// sans eux, la valeur est perdue.
    static func shortcutArgument(keyCode: Int, carbonModifiers: Int) -> String {
        #""{\"carbonKeyCode\":\#(keyCode),\"carbonModifiers\":\#(carbonModifiers)}""#
    }

    /// Mini-fenêtres ouvertes (identifiant du panneau ; repli : les fenêtres qui ont le bouton × de la mini-fenêtre).
    @MainActor
    func miniWindows(in app: XCUIApplication) -> XCUIElementQuery {
        let byIdentifier = app.windows.matching(identifier: "miniWindow")
        return byIdentifier.count > 0 ? byIdentifier : app.windows.containing(.button, identifier: "miniWindowClose")
    }

    /// Fenêtre de navigation principale (ni mini-fenêtre ni fenêtre privée).
    @MainActor
    func browserWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows.containing(.button, identifier: "newTabButton")
            .matching(NSPredicate(format: "title != %@", "Navigation privée"))
            .firstMatch
    }

    /// Bouton « Ouvrir dans ‹Space› » de `mini` ; sa valeur est le nom du Space visé.
    @MainActor
    func openInSpaceButton(in mini: XCUIElement) -> XCUIElement {
        mini.descendants(matching: .any).matching(identifier: "miniWindowOpenInSpace").firstMatch
    }

    /// Fichier > Nouvelle mini-fenêtre : la mini-fenêtre s'ouvre, barre ouverte, son champ a le clavier.
    @MainActor
    @discardableResult
    func openMiniWindow(in app: XCUIApplication) -> XCUIElement {
        let count = miniWindows(in: app).count
        app.menuBars.menuBarItems["Fichier"].click()
        app.menuBars.menuItems["Nouvelle mini-fenêtre"].click()
        XCTAssertTrue(waitForCount(miniWindows(in: app), count + 1, timeout: 5))
        // La nouvelle est la seule dont la barre est ouverte : les autres ont perdu le clavier, leur barre s'est fermée.
        // On la désigne ensuite par son rang, et non par ce champ, qui disparaît dès qu'une adresse est validée.
        let windows = miniWindows(in: app)
        XCTAssertTrue(windows.containing(.textField, identifier: "addressField").firstMatch.waitForExistence(timeout: 3))
        let index = windows.allElementsBoundByIndex.firstIndex { $0.textFields["addressField"].exists } ?? 0
        let mini = windows.element(boundBy: index)
        let field = addressField(in: mini)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForKeyboardFocus(of: field))
        return mini
    }

    /// Tape `text` puis Entrée dans la barre de `mini` (déjà ouverte), et attend que la pastille l'affiche.
    @MainActor
    func load(_ text: String, in mini: XCUIElement, app: XCUIApplication) {
        let field = addressField(in: mini)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        app.typeText("\(text)\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForValue(of: addressPill(in: mini)) { $0 == text })
    }

    /// Point de la fenêtre de navigation que la mini-fenêtre ne couvre pas (au bord de la barre latérale ou de la
    /// page, sur le fond).
    @MainActor
    func uncoveredPoint(of browser: XCUIElement, avoiding mini: XCUIElement) -> XCUICoordinate {
        let offsets = [CGVector(dx: 0.05, dy: 0.5), CGVector(dx: 0.95, dy: 0.5), CGVector(dx: 0.5, dy: 0.05), CGVector(dx: 0.5, dy: 0.95)]
        let frame = browser.frame
        let miniFrame = mini.frame
        let chosen = offsets.first { offset in
            !miniFrame.contains(CGPoint(x: frame.minX + frame.width * offset.dx, y: frame.minY + frame.height * offset.dy))
        } ?? offsets[0]
        return browser.coordinate(withNormalizedOffset: chosen)
    }
}
