import SwiftUI

/// Button of the sidebar that hides or shows it.
struct SidebarToggle {
    /// Sidebar shown (otherwise: floating, appeared on hovering the edge).
    let isVisible: Bool
    let toggle: () -> Void

    var title: LocalizedStringKey {
        isVisible ? "Hide Sidebar" : "Show Sidebar"
    }
}
