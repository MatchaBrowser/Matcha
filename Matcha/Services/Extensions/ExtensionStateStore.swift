import Foundation
import OSLog

/// States of the installed extensions, by identifier (task 6.3), saved in the app's settings (`installedExtensions`,
/// JSON); without `defaults` (tests, test store), everything stays in memory. Read entry by entry: an unreadable one
/// is dropped alone, and the saved value is first copied to `installedExtensions.unreadable` (audit R4). The
/// extensions themselves are folders (`ExtensionInstallDirectory`). Observed: the settings follow every change (audit
/// C7).
@MainActor
@Observable
final class ExtensionStateStore {
    static let defaultsKey = "installedExtensions"
    /// Copy of a saved value that couldn't be read entirely, kept before it is written over.
    static let unreadableKey = "installedExtensions.unreadable"

    @ObservationIgnored private let defaults: UserDefaults?
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
            Logger.extensions.error("Extension states not saved: \(error.logSummary, privacy: .public)")
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
                Logger.extensions.error("\(entries.count - states.count, privacy: .public) unreadable extension state(s), set aside")
            }
            return states
        } catch {
            defaults?.set(data, forKey: unreadableKey)
            Logger.extensions.error("Unreadable extension states, set aside: \(error.logSummary, privacy: .public)")
            return [:]
        }
    }
}
