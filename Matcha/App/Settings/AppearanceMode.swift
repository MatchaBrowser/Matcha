import AppKit

/// App appearance: the system's, or always light, or always dark.
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

    /// Name of the AppKit appearance to force, nil to follow the system.
    var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }

    /// Applies the appearance to the whole app: windows, menus and web pages (`prefers-color-scheme`).
    @MainActor
    func apply() {
        NSApp.appearance = appearanceName.flatMap(NSAppearance.init(named:))
    }
}
