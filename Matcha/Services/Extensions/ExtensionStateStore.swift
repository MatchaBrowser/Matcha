import Foundation
import OSLog

/// Ce que Matcha retient d'une extension installée (tâche 6.3) : active ou non, et les décisions de l'utilisateur sur ses
/// permissions, que WebKit ne garde pas d'un lancement à l'autre (`WKWebExtensionContext.grantedPermissions` et
/// suivants : « This value should be saved and restored as needed by the app »). Clés en texte : nom de la permission
/// (« tabs ») ou motif d'adresses (« *://*.example.com/* ») ; valeur : date d'expiration (`Date.distantFuture` sans
/// expiration). Type pur.
nonisolated struct ExtensionState: Codable, Equatable, Sendable {
    var isEnabled = true
    var grantedPermissions: [String: Date] = [:]
    var grantedMatchPatterns: [String: Date] = [:]
    var deniedPermissions: [String: Date] = [:]
    var deniedMatchPatterns: [String: Date] = [:]
    /// Fenêtres privées : refusées par défaut, comme dans Safari ; seul l'utilisateur les ouvre à une extension (6.4).
    var hasAccessToPrivateData = false
    var hasRequestedOptionalAccessToAllHosts = false
    /// Extension Safari d'une app (tâche 6.4) : chemin de son `.appex`, chargé sur place ; nil pour une extension copiée
    /// dans le dossier des extensions.
    var appExtensionPath: String?

    /// Sans les décisions expirées à `date`.
    func removingExpired(at date: Date) -> ExtensionState {
        var state = self
        state.grantedPermissions = grantedPermissions.filter { $0.value > date }
        state.grantedMatchPatterns = grantedMatchPatterns.filter { $0.value > date }
        state.deniedPermissions = deniedPermissions.filter { $0.value > date }
        state.deniedMatchPatterns = deniedMatchPatterns.filter { $0.value > date }
        return state
    }
}

/// États des extensions installées, par identifiant (tâche 6.3), enregistrés dans les réglages de l'app
/// (`installedExtensions`, JSON) ; sans `defaults` (tests, base de test), tout reste en mémoire. Les extensions
/// elles-mêmes sont des dossiers (`ExtensionInstallDirectory`).
@MainActor
final class ExtensionStateStore {
    static let defaultsKey = "installedExtensions"

    private let defaults: UserDefaults?
    private var states: [String: ExtensionState]

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        states = Self.load(from: defaults)
    }

    /// Identifiants connus.
    var identifiers: [String] {
        states.keys.sorted()
    }

    /// Extensions Safari d'apps installées (tâche 6.4) : (identifiant, `.appex`), triées par identifiant.
    var appExtensions: [(identifier: String, url: URL)] {
        states.compactMap { entry in entry.value.appExtensionPath.map { (entry.key, URL(filePath: $0)) } }
            .sorted { $0.identifier < $1.identifier }
    }

    /// État retenu de l'extension `identifier`, nil si elle n'a jamais été chargée.
    func state(for identifier: String) -> ExtensionState? {
        states[identifier]
    }

    /// Retient `state` ; rien n'est écrit s'il ne change pas.
    func setState(_ state: ExtensionState, for identifier: String) {
        guard states[identifier] != state else {
            return
        }
        states[identifier] = state
        save()
    }

    /// Oublie une extension désinstallée.
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
