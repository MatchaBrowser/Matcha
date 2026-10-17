import XCTest

/// Impression, export en PDF et zoom (tâche 5.4) : badge du zoom, ligne « Zoom » des réglages du site, menus.
extension XCTestCase {
    /// Badge du zoom à côté de la pastille d'adresse (barre latérale, barre au-dessus de la page, aperçu, mini-fenêtre),
    /// absent à 100 % ; son libellé est « Zoom de la page », sa valeur « 115 % ». `scope` : l'app, l'aperçu (`peek`)…
    @MainActor
    func zoomBadge(in scope: XCUIElement) -> XCUIElement {
        zoomBadges(in: scope).firstMatch
    }

    @MainActor
    func zoomBadges(in scope: XCUIElement) -> XCUIElementQuery {
        scope.descendants(matching: .any).matching(identifier: "zoomBadge")
    }

    /// `text` avec des espaces ordinaires : le français sépare le nombre de « % » par une espace insécable (fine ou
    /// non, selon la version d'ICU).
    nonisolated static func normalizedSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// Attend que `text` (libellé ou valeur de `element`, espaces normalisées) se termine par « `percent` % ».
    @MainActor
    func waitForPercent(_ percent: Int, of element: XCUIElement, inValue: Bool = false, timeout: TimeInterval = 3) -> Bool {
        let expected = "\(percent) %"
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement, element.exists else {
                return false
            }
            let text = inValue ? element.value as? String ?? "" : element.label
            return Self.normalizedSpaces(text).hasSuffix(expected)
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    /// Tape `key` avec ⌘ (« + », « = », « - », « 0 ») puis attend le badge « `percent` % » de la page affichée, ou sa
    /// disparition pour 100 %.
    @MainActor
    func zoom(_ key: String, expecting percent: Int, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        app.typeKey(key, modifierFlags: .command)
        let badge = zoomBadge(in: app)
        let shown = percent == 100 ? badge.waitForNonExistence(timeout: 3) : waitForPercent(percent, of: badge, inValue: true)
        XCTAssertTrue(shown, "⌘\(key) : \(percent) % attendu", file: file, line: line)
    }

    /// Élément de la ligne « Zoom » des réglages du site : `siteZoomOutButton`, `siteZoomResetButton` (sa valeur est le
    /// zoom affiché), `siteZoomInButton`.
    @MainActor
    func siteZoomButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons[identifier].firstMatch
    }

    /// Élément de menu `title` (barre des menus) devenu (in)actif.
    @MainActor
    func waitForMenuItem(_ title: String, enabled: Bool, in app: XCUIApplication, timeout: TimeInterval = 3) -> Bool {
        let item = app.menuBars.menuItems[title]
        guard item.waitForExistence(timeout: timeout) else {
            return false
        }
        let predicate = NSPredicate(format: "isEnabled == %@", NSNumber(value: enabled))
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: item)], timeout: timeout) == .completed
    }

    /// Feuille ouverte sur la fenêtre de navigation (zone d'impression, zone d'enregistrement).
    @MainActor
    func windowSheet(in app: XCUIApplication) -> XCUIElement {
        app.sheets.firstMatch
    }
}
