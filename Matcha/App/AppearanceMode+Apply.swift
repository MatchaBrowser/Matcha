import AppKit

nonisolated extension AppearanceMode {
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
