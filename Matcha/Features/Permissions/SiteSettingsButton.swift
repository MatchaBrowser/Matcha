import SwiftUI

/// Site settings button (task 5.2), to the right of the address pill: visible when the displayed page is a website
/// (http or https). It opens and closes the panel; highlighted while the panel is open.
struct SiteSettingsButton: View {
    let tab: BrowserTab?
    let isPresented: Bool
    let action: () -> Void

    var body: some View {
        if SiteOrigin.web(of: tab?.url) != nil {
            Button(action: action) {
                Label { title } icon: { Image(systemName: "switch.2") }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(SidebarIconButtonStyle())
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(isPresented ? 0.12 : 0)))
            .help(title)
            .accessibilityAddTraits(isPresented ? .isSelected : [])
            .accessibilityIdentifier("siteSettingsButton")
        }
    }

    private var title: Text {
        Text("Site Settings", comment: "Button next to the address: permissions and data of the website shown")
    }
}
