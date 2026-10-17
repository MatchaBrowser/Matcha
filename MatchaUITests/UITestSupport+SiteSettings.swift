import XCTest

/// Réglages du site (tâche 5.2) : bouton, panneau et menus des permissions.
extension XCTestCase {
    /// Bouton des réglages du site, à droite de la pastille d'adresse.
    @MainActor
    func siteSettingsButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons["siteSettingsButton"].firstMatch
    }

    @MainActor
    func siteSettingsPanel(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "siteSettingsPanel").firstMatch
    }

    enum SitePermissionPickerKind: String {
        case camera, microphone
    }

    /// Menu « Demander / Autoriser / Refuser » d'une permission ; sa valeur est le choix affiché.
    @MainActor
    func permissionPicker(_ kind: SitePermissionPickerKind, in app: XCUIApplication) -> XCUIElement {
        app.popUpButtons["sitePermissionPicker-\(kind.rawValue)"].firstMatch
    }
}
