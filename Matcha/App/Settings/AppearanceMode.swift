import AppKit

/// Apparence de l'app : celle du système, ou toujours claire, ou toujours sombre.
nonisolated enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self {
        self
    }

    var title: LocalizedStringResource {
        switch self {
        case .system: LocalizedStringResource("System", comment: "Appearance option that follows the macOS setting")
        case .light: LocalizedStringResource("Light", comment: "Appearance option")
        case .dark: LocalizedStringResource("Dark", comment: "Appearance option")
        }
    }

    /// Nom de l'apparence AppKit à imposer, nil pour suivre le système.
    var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }

    /// Applique l'apparence à toute l'app : fenêtres, menus et pages web (`prefers-color-scheme`).
    @MainActor
    func apply() {
        NSApp.appearance = appearanceName.flatMap(NSAppearance.init(named:))
    }
}
