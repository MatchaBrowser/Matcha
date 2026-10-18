import Foundation

/// Réglages de la mise en veille lus à chaque vérification : délai (nil : jamais) et intervalle entre deux
/// vérifications.
nonisolated struct TabSuspensionSettings: Equatable, Sendable {
    /// Une vérification par minute : un onglet est mis en veille au plus une minute après son délai.
    static let defaultCheckInterval = Duration.seconds(60)
    /// Argument de lancement des tests d'interface, en Debug seulement : délai en secondes (il l'emporte sur le
    /// réglage, « Jamais » compris), vérifié chaque seconde.
    static let testDelayKey = "tabSuspensionDelaySeconds"

    let delay: Duration?
    let checkInterval: Duration

    static func current(in defaults: UserDefaults = .standard) -> Self {
        #if DEBUG
            if defaults.object(forKey: testDelayKey) != nil {
                return Self(delay: .seconds(max(1, defaults.integer(forKey: testDelayKey))), checkInterval: .seconds(1))
            }
        #endif
        return Self(delay: BrowserSettings.tabSuspensionDelay(in: defaults).duration, checkInterval: defaultCheckInterval)
    }
}
