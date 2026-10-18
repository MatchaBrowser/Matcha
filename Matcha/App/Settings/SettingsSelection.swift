import Observation

/// Onglet affiché par les réglages (⌘,), le temps de la session de l'app : « Gérer les extensions… » (bouton d'une
/// extension, tâche 6.5) ouvre directement l'onglet Extensions.
@MainActor
@Observable
final class SettingsSelection {
    enum Tab: Hashable {
        case general
        case appearance
        case profiles
        case privacy
        case extensions
        case advanced
    }

    static let shared = SettingsSelection()

    var tab = Tab.general
}
