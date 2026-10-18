import Foundation

/// Un réglage de l'app (`SYNC.md` § 2.6) : sa clé et sa valeur telle que l'app la garde.
nonisolated struct SyncSettingFields: Codable, Equatable, Sendable {
    var key: String
    var value: SyncJSON

    /// Clé de la liste des réglages synchronisés, valeur connue.
    var isValid: Bool {
        SyncedSettings.isValid(value, for: key)
    }
}

/// Décision d'un profil pour une origine et une permission (`SitePermissionRecord`).
nonisolated struct SyncSitePermissionFields: Codable, Equatable, Sendable {
    var origin: String
    var kind: String
    var decision: String
    var profileId: UUID?

    var isValid: Bool {
        !origin.isEmpty && SitePermissionKind(rawValue: kind) != nil && SitePermissionDecision(rawValue: decision) != nil
    }
}

/// Zoom retenu pour un site (`siteZoomLevels`).
nonisolated struct SyncSiteZoomFields: Codable, Equatable, Sendable {
    var site: String
    var level: Double

    var isValid: Bool {
        !site.isEmpty && (0.5 ... 3).contains(level)
    }
}

/// Réglages de l'app synchronisés et leurs valeurs (`SYNC.md` § 2.6). Une clé absente de la liste, ou une valeur
/// inconnue, est ignorée à la réception. Type pur.
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
    ]

    /// Clés synchronisées, triées.
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

    /// Valeur d'un réglage telle que `UserDefaults` la rend, en JSON ; nil si elle n'est pas d'un genre attendu pour
    /// `key` (un argument de lancement « YES » pour un booléen compte comme `true`).
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

    /// Valeur à écrire dans `UserDefaults` pour `value`.
    static func defaultsValue(of value: SyncJSON) -> Any? {
        switch value {
        case let .bool(flag): flag
        case let .number(number): Int(number)
        case let .string(text): text
        default: nil
        }
    }
}
