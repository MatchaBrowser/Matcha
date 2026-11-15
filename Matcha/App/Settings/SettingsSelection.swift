import Foundation
import Observation

/// Tab shown by the settings (⌘,), for the duration of the app session: “Manage Extensions…” (an extension's
/// button, task 6.5) opens the Extensions tab directly.
@MainActor
@Observable
final class SettingsSelection {
    enum Tab: Hashable, CaseIterable {
        case general
        case shortcuts
        case appearance
        case profiles
        case privacy
        case extensions
        case sync
        case vault
        case advanced
    }

    var tab = Tab.general
}

extension SettingsSelection.Tab {
    /// The tab's name in the window's toolbar: every name must fit in `SettingsView.width`, in each language
    /// (`SettingsToolbarTests`); otherwise the last tabs go into an overflow menu where they can't be chosen.
    var title: LocalizedStringResource {
        switch self {
        case .general: LocalizedStringResource("General", comment: "Settings tab")
        case .shortcuts: LocalizedStringResource("Shortcuts", comment: "Settings tab")
        case .appearance: LocalizedStringResource("Appearance", comment: "Settings tab and appearance picker")
        case .profiles: LocalizedStringResource("Profiles", comment: "Settings tab")
        case .privacy: LocalizedStringResource("Privacy", comment: "Settings tab")
        case .extensions: LocalizedStringResource("Extensions", comment: "Settings tab")
        case .sync: LocalizedStringResource("Sync", comment: "Settings: Sync tab, section and mode picker")
        case .vault: LocalizedStringResource("Vault", comment: "Title of the vault's window")
        case .advanced: LocalizedStringResource("Advanced", comment: "Settings: tab of advanced settings")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .appearance: "paintbrush"
        case .profiles: "person.2"
        case .privacy: "hand.raised"
        case .extensions: "puzzlepiece.extension"
        case .sync: "arrow.triangle.2.circlepath"
        case .vault: "lock.rectangle.stack"
        case .advanced: "gearshape.2"
        }
    }
}
