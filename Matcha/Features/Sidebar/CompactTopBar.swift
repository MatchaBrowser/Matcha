import SwiftUI

/// Bar across the top of the window when the hidden sidebar is reduced to icons (`CompactSidebar`): room for the
/// window's buttons, the button that shows the sidebar again, back, forward, reload and Home, then the address when the
/// settings put it in the sidebar. Its empty part moves the window; a double click zooms it (window background).
struct CompactTopBar: View {
    let tab: BrowserTab?
    /// The address bar is in the sidebar (setting): it comes here, with the navigation.
    let showsAddress: Bool
    let showsNavigationButtons: Bool
    var goHome: (() -> Void)?
    let sidebarToggle: SidebarToggle
    let editAddress: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SidebarTopBar(
                tab: tab,
                showsNavigationButtons: showsAddress && showsNavigationButtons,
                goHome: showsAddress ? goHome : nil,
                sidebarToggle: sidebarToggle,
            )
            .fixedSize(horizontal: true, vertical: false)
            if showsAddress {
                AddressPill(tab: tab, edit: editAddress)
                    .frame(maxWidth: 420)
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, BrowserWindowView.cardMargin)
        .frame(height: SidebarTopBar.height)
    }
}
