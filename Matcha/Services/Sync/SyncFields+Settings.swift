import Foundation

/// An app setting (`SYNC.md` § 2.6): its key and its value as the app stores it.
nonisolated struct SyncSettingFields: Codable, Equatable, Sendable {
    var key: String
    var value: SyncJSON

    /// Key from the list of synced settings, known value.
    var isValid: Bool {
        SyncedSettings.isValid(value, for: key)
    }
}

/// A profile's decision for an origin and a permission (`SitePermissionRecord`).
nonisolated struct SyncSitePermissionFields: Codable, Equatable, Sendable {
    var origin: String
    var kind: String
    var decision: String
    var profileId: UUID?

    var isValid: Bool {
        !origin.isEmpty && SitePermissionKind(rawValue: kind) != nil && SitePermissionDecision(rawValue: decision) != nil
    }
}

/// Zoom level remembered for a website (`siteZoomLevels`).
nonisolated struct SyncSiteZoomFields: Codable, Equatable, Sendable {
    var site: String
    var level: Double

    var isValid: Bool {
        !site.isEmpty && (0.5 ... 3).contains(level)
    }
}

/// Synced app settings and their values (`SYNC.md` § 2.6). A key missing from the list, or an unknown value, is
/// ignored on reception. Pure type.
nonisolated enum SyncedSettings {
    private enum Kind {
        case choice(Set<String>)
        case boolean
        case text
        case minutes(Set<Int>)
    }

    private static let kinds: [String: Kind] = [
        BrowserSettings.Key.searchEngine: .choice(Set(SearchEngine.allCases.map(\.rawValue))),
        BrowserSettings.Key.appearance: .choice(Set(AppearanceMode.allCases.map(\.rawValue))),
        BrowserSettings.Key.confirmBeforeQuitting: .boolean,
        BrowserSettings.Key.showsHomeButton: .boolean,
        BrowserSettings.Key.showsNavigationButtons: .boolean,
        BrowserSettings.Key.showsSearchSuggestions: .boolean,
        BrowserSettings.Key.opensPinnedLinksInPeek: .boolean,
        BrowserSettings.Key.homePage: .text,
        BrowserSettings.Key.newTabPage: .choice(Set(NewTabPage.allCases.map(\.rawValue))),
        BrowserSettings.Key.addressBarPosition: .choice(Set(AddressBarPosition.allCases.map(\.rawValue))),
        BrowserSettings.Key.tabSuspensionDelay: .minutes(Set(TabSuspensionDelay.allCases.map(\.rawValue))),
        BrowserSettings.Key.externalLinkDestination: .choice(Set(ExternalLinkDestination.allCases.map(\.rawValue))),
    ]

    /// Synced keys, sorted.
    static var keys: [String] {
        kinds.keys.sorted()
    }

    static func isValid(_ value: SyncJSON, for key: String) -> Bool {
        switch (kinds[key], value) {
        case let (.choice(values), .string(text)): values.contains(text)
        case (.boolean, .bool): true
        case (.text, .string): true
        case let (.minutes(values), .number(number)): number == number.rounded() && values.contains(Int(number))
        default: false
        }
    }

    /// Value of a setting as `UserDefaults` returns it, as JSON; nil if it is not of an expected kind for `key` (a
    /// launch argument “YES” for a Boolean counts as `true`).
    static func value(_ object: Any, for key: String) -> SyncJSON? {
        let value: SyncJSON? = switch kinds[key] {
        case .boolean:
            if let number = object as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
                .bool(number.boolValue)
            } else if let text = object as? String {
                ["YES", "true", "1"].contains(text) ? .bool(true) : ["NO", "false", "0"].contains(text) ? .bool(false) : nil
            } else {
                nil
            }
        case .minutes:
            (object as? NSNumber).map { .number($0.doubleValue) } ?? (object as? String).flatMap(Double.init).map(SyncJSON.number)
        case .choice, .text:
            (object as? String).map(SyncJSON.string)
        case nil:
            nil
        }
        return value.flatMap { isValid($0, for: key) ? $0 : nil }
    }

    /// Value to write to `UserDefaults` for `value`.
    static func defaultsValue(of value: SyncJSON) -> Any? {
        switch value {
        case let .bool(flag): flag
        case let .number(number): Int(number)
        case let .string(text): text
        default: nil
        }
    }
}
