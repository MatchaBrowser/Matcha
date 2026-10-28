import SwiftUI

/// Full-width address bar at the top of a card: navigation and Home buttons, the address of this card's tab, its zoom
/// badge, the extension buttons (task 6.5), then the site settings button.
struct AddressToolbar: View {
    let tab: BrowserTab?
    /// Opens the command bar on the address of the displayed tab.
    let editAddress: () -> Void
    let showsNavigationButtons: Bool
    var goHome: (() -> Void)?
    /// Site settings panel open on this card (highlighted button).
    var isSiteSettingsPresented = false
    /// Site settings button (task 5.2); nil to hide it.
    var toggleSiteSettings: (() -> Void)?
    /// Per-site zoom of the window, reset to 100% by a click on the zoom badge (task 5.4).
    var siteZooms: SiteZoomStore?
    /// Private window: only the extensions that have access to it have their button.
    var isPrivate = false

    var body: some View {
        HStack(spacing: 4) {
            NavigationButtons(tab: tab, showsHistoryButtons: showsNavigationButtons, goHome: goHome)
            AddressPill(tab: tab, edit: editAddress)
            ZoomBadge(page: tab, siteZooms: siteZooms)
            TranslateButton(page: tab)
            ExtensionButtonsRow(tab: tab, isPrivate: isPrivate)
            if let toggleSiteSettings {
                SiteSettingsButton(tab: tab, isPresented: isSiteSettingsPresented, action: toggleSiteSettings)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(SidebarIconButtonStyle())
        .animatesZoomBadge(of: tab)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
