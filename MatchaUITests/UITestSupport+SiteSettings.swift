import XCTest

/// Site settings (task 5.2): button, panel and permission menus.
extension XCTestCase {
    /// Site settings button, right of the address pill.
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

    /// “Ask / Allow / Deny” menu of a permission; its value is the displayed choice.
    @MainActor
    func permissionPicker(_ kind: SitePermissionPickerKind, in app: XCUIApplication) -> XCUIElement {
        app.popUpButtons["sitePermissionPicker-\(kind.rawValue)"].firstMatch
    }
}
