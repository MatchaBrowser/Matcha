import Foundation
import OSLog

/// What Matcha remembers about an installed extension (task 6.3): enabled or not, and the user's decisions about its
/// permissions, which WebKit does not keep from one launch to the next (`WKWebExtensionContext.grantedPermissions` and
/// following: “This value should be saved and restored as needed by the app”). Keys as text: name of the permission
/// (“tabs”) or address pattern (“*://*.example.com/*”); value: expiration date (`Date.distantFuture` without
/// expiration). Pure type.
nonisolated struct ExtensionState: Codable, Equatable, Sendable {
    var isEnabled = true
    var grantedPermissions: [String: Date] = [:]
    var grantedMatchPatterns: [String: Date] = [:]
    var deniedPermissions: [String: Date] = [:]
    var deniedMatchPatterns: [String: Date] = [:]
    /// Private windows: denied by default, as in Safari; only the user opens them to an extension (6.4).
    var hasAccessToPrivateData = false
    var hasRequestedOptionalAccessToAllHosts = false
    /// Safari extension of an app (task 6.4): path of its `.appex`, loaded in place; nil for an extension copied into
    /// the extensions folder.
    var appExtensionPath: String?
    /// Button next to the address (task 6.5): false if it is hidden; nil (default): shown.
    var showsButton: Bool?

    init() {}

    /// A missing field takes its default value: a field added later doesn't make the saved states unreadable
    /// (audit R4).
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        grantedPermissions = try container.decodeIfPresent([String: Date].self, forKey: .grantedPermissions) ?? [:]
        grantedMatchPatterns = try container.decodeIfPresent([String: Date].self, forKey: .grantedMatchPatterns) ?? [:]
        deniedPermissions = try container.decodeIfPresent([String: Date].self, forKey: .deniedPermissions) ?? [:]
        deniedMatchPatterns = try container.decodeIfPresent([String: Date].self, forKey: .deniedMatchPatterns) ?? [:]
        hasAccessToPrivateData = try container.decodeIfPresent(Bool.self, forKey: .hasAccessToPrivateData) ?? false
        hasRequestedOptionalAccessToAllHosts = try container
            .decodeIfPresent(Bool.self, forKey: .hasRequestedOptionalAccessToAllHosts) ?? false
        appExtensionPath = try container.decodeIfPresent(String.self, forKey: .appExtensionPath)
        showsButton = try container.decodeIfPresent(Bool.self, forKey: .showsButton)
    }

    /// Without the decisions expired at `date`.
    func removingExpired(at date: Date) -> ExtensionState {
        var state = self
        state.grantedPermissions = grantedPermissions.filter { $0.value > date }
        state.grantedMatchPatterns = grantedMatchPatterns.filter { $0.value > date }
        state.deniedPermissions = deniedPermissions.filter { $0.value > date }
        state.deniedMatchPatterns = deniedMatchPatterns.filter { $0.value > date }
        return state
    }
}

/// States of the installed extensions, by identifier (task 6.3), saved in the app's settings (`installedExtensions`,
/// JSON); without `defaults` (tests, test store), everything stays in memory. Read entry by entry: an unreadable one
/// is dropped alone, and the saved value is first copied to `installedExtensions.unreadable` (audit R4). The extensions themselves are
/// folders
/// (`ExtensionInstallDirectory`).
@MainActor
final class ExtensionStateStore {
    static let defaultsKey = "installedExtensions"
    /// Copy of a saved value that couldn't be read entirely, kept before it is written over.
    static let unreadableKey = "installedExtensions.unreadable"

    private let defaults: UserDefaults?
    private var states: [String: ExtensionState]

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        states = Self.load(from: defaults)
    }

    /// Known identifiers.
    var identifiers: [String] {
        states.keys.sorted()
    }

    /// Installed Safari extensions of apps (task 6.4): (identifier, `.appex`), sorted by identifier.
    var appExtensions: [(identifier: String, url: URL)] {
        states.compactMap { entry in entry.value.appExtensionPath.map { (entry.key, URL(filePath: $0)) } }
            .sorted { $0.identifier < $1.identifier }
    }

    /// Remembered state of extension `identifier`, nil if it has never been loaded.
    func state(for identifier: String) -> ExtensionState? {
        states[identifier]
    }

    /// Remembers `state`; nothing is written if it does not change.
    func setState(_ state: ExtensionState, for identifier: String) {
        guard states[identifier] != state else {
            return
        }
        states[identifier] = state
        save()
    }

    /// Forgets an uninstalled extension.
    func removeState(for identifier: String) {
        guard states.removeValue(forKey: identifier) != nil else {
            return
        }
        save()
    }

    private func save() {
        guard let defaults else {
            return
        }
        do {
            try defaults.set(JSONEncoder().encode(states), forKey: Self.defaultsKey)
        } catch {
            Logger.extensions.error("États des extensions non enregistrés : \(error.logSummary, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults?) -> [String: ExtensionState] {
        guard let data = defaults?.data(forKey: defaultsKey) else {
            return [:]
        }
        do {
            let entries = try JSONDecoder().decode([String: Lenient<ExtensionState>].self, from: data)
            let states = entries.compactMapValues(\.value)
            if states.count < entries.count {
                defaults?.set(data, forKey: unreadableKey)
                Logger.extensions.error("\(entries.count - states.count, privacy: .public) état(s) d'extension illisible(s), mis de côté")
            }
            return states
        } catch {
            defaults?.set(data, forKey: unreadableKey)
            Logger.extensions.error("États des extensions illisibles, mis de côté : \(error.logSummary, privacy: .public)")
            return [:]
        }
    }
}
