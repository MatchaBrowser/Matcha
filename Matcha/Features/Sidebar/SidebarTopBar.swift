import SwiftUI

/// Top row of the sidebar: room for the window's buttons, a button that hides or shows the sidebar (like ⌃⌘S),
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
