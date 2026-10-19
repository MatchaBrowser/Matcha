import SwiftUI

/// Top row of the sidebar: room for the window's buttons, a button that hides or shows the sidebar (like ⌘S),
/// then, depending on the settings, back, forward, reload and Home.
struct SidebarTopBar: View {
    static let height = 32.0
    /// Room for the window's red, orange and green buttons.
    static let windowButtonsWidth = 70.0

    let tab: BrowserTab?
    var showsNavigationButtons = true
    /// Action of the Home button; nil to not display it.
    var goHome: (() -> Void)?
    /// Hides the sidebar (shown) or pins it (floating sidebar); nil to not display the button.
    var sidebarToggle: SidebarToggle?

    var body: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: Self.windowButtonsWidth)
            if let sidebarToggle {
                Button(action: sidebarToggle.toggle) {
                    Label(sidebarToggle.title, systemImage: "sidebar.left")
                }
                .help(sidebarToggle.title)
                .accessibilityIdentifier("sidebarToggleButton")
            }
            Spacer(minLength: 0)
            NavigationButtons(tab: tab, showsHistoryButtons: showsNavigationButtons, goHome: goHome)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(SidebarIconButtonStyle())
        .frame(height: Self.height)
    }
}

/// Button of the sidebar that hides or shows it.
struct SidebarToggle {
    /// Sidebar shown (otherwise: floating, appeared on hovering the edge).
    let isVisible: Bool
    let toggle: () -> Void

    var title: LocalizedStringKey {
        isVisible ? "Hide Sidebar" : "Show Sidebar"
    }
}

/// Square icon button of the sidebar, highlighted on hover.
struct SidebarIconButtonStyle: ButtonStyle {
    /// Side of the button, in points.
    static let size = 26.0

    func makeBody(configuration: Configuration) -> some View {
        SidebarIconButton(configuration: configuration)
    }
}

private struct SidebarIconButton: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(width: SidebarIconButtonStyle.size, height: SidebarIconButtonStyle.size)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered && isEnabled ? 0.1 : 0)),
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 0.85) : 0.3)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}
