import Foundation

/// Où s'ouvrent les liens cliqués dans d'autres apps (tâche 8.2).
nonisolated enum ExternalLinkDestination: String, CaseIterable, Identifiable, Sendable {
    /// Une mini-fenêtre par lien, comme Little Arc : on lit, puis on garde la page (⌘O) ou on la ferme.
    case miniWindow
    /// Un nouvel onglet du Space affiché par la fenêtre principale.
    case space

    var id: Self {
        self
    }

    var title: LocalizedStringResource {
        switch self {
        case .miniWindow: "A Mini Window"
        case .space: "A New Tab in the Current Space"
        }
    }

    /// Valeur du réglage dans `defaults`, ou sa valeur par défaut.
    static func current(in defaults: UserDefaults = .standard) -> ExternalLinkDestination {
        defaults.string(forKey: BrowserSettings.Key.externalLinkDestination).flatMap(Self.init(rawValue:))
            ?? BrowserSettings.externalLinkDestination
    }
}
