import SwiftUI

/// Bouton des réglages du site (tâche 5.2), à droite de la pastille d'adresse : visible quand la page affichée est
/// un site web (http ou https). Il ouvre et ferme le panneau ; surligné tant que le panneau est ouvert.
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
