import XCTest

/// Printing, PDF export and zoom (task 5.4): zoom badge, “Zoom” row of the site settings, menus.
extension XCTestCase {
    /// Zoom badge next to the address pill (sidebar, bar above the page, Peek, mini window), absent at 100 %;
    /// its label is “Page Zoom”, its value “115 %”. `scope`: the app, Peek (`peek`)…
    @MainActor
    func zoomBadge(in scope: XCUIElement) -> XCUIElement {
        zoomBadges(in: scope).firstMatch
    }

    @MainActor
    func zoomBadges(in scope: XCUIElement) -> XCUIElementQuery {
        scope.descendants(matching: .any).matching(identifier: "zoomBadge")
    }

    /// `text` with ordinary spaces: French separates the number from “%” with a no-break space (narrow or
    /// not, depending on the ICU version).
    nonisolated static func normalizedSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// Waits for `text` (label or value of `element`, spaces normalized) to end with “`percent` %”.
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

    /// Types `key` with ⌘ (“+”, “=”, “-”, “0”) then waits for the “`percent` %” badge of the displayed page, or
    /// for it to disappear at 100 %.
    @MainActor
    func zoom(_ key: String, expecting percent: Int, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        app.typeKey(key, modifierFlags: .command)
        let badge = zoomBadge(in: app)
        let shown = percent == 100 ? badge.waitForNonExistence(timeout: 3) : waitForPercent(percent, of: badge, inValue: true)
        XCTAssertTrue(shown, "⌘\(key): \(percent)% expected", file: file, line: line)
    }

    /// Element of the “Zoom” row of the site settings: `siteZoomOutButton`, `siteZoomResetButton` (its value is
    /// the displayed zoom), `siteZoomInButton`.
    @MainActor
    func siteZoomButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons[identifier].firstMatch
    }

    /// Menu item `title` (menu bar) once it becomes enabled (or disabled).
    @MainActor
    func waitForMenuItem(_ title: String, enabled: Bool, in app: XCUIApplication, timeout: TimeInterval = 3) -> Bool {
        let item = app.menuBars.menuItems[title]
        guard item.waitForExistence(timeout: timeout) else {
            return false
        }
        let predicate = NSPredicate(format: "isEnabled == %@", NSNumber(value: enabled))
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: item)], timeout: timeout) == .completed
    }

    /// Sheet open on the browser window (print panel, save panel).
    @MainActor
    func windowSheet(in app: XCUIApplication) -> XCUIElement {
        app.sheets.firstMatch
    }
}
