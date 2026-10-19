import Foundation

/// Position of the address bar.
nonisolated enum AddressBarPosition: String, CaseIterable, Identifiable, Sendable {
    /// At the top of the sidebar, as in Arc.
    case sidebar
    /// At the top of the content card, across its full width, with the navigation buttons.
    case top

    var id: Self {
        self
    }

    var title: LocalizedStringResource {
        switch self {
        case .sidebar: "In the Sidebar"
        case .top: "Above the Page"
        }
    }
}
