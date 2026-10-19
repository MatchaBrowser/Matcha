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
/// JSON); without `defaults` (tests, test store), everything stays in memory. The extensions themselves are folders
/// (`ExtensionInstallDirectory`).
@MainActor
final class ExtensionStateStore {
    static let defaultsKey = "installedExtensions"

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
            Logger.extensions.error("États des extensions non enregistrés : \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults?) -> [String: ExtensionState] {
        guard let data = defaults?.data(forKey: defaultsKey) else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: ExtensionState].self, from: data)
        } catch {
            Logger.extensions.error("États des extensions illisibles, ignorés : \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }
}
