import Foundation

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
}
