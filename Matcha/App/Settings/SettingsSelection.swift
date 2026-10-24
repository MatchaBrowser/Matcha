import Observation

/// Tab shown by the settings (⌘,), for the duration of the app session: “Manage Extensions…” (an extension's
/// button, task 6.5) opens the Extensions tab directly.
@MainActor
@Observable
final class SettingsSelection {
    enum Tab: Hashable {
        case general
        case shortcuts
        case appearance
        case profiles
        case privacy
        case extensions
        case sync
        case advanced
    }

    var tab = Tab.general
}
