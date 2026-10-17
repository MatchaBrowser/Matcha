import SwiftUI

/// Ligne du haut de la barre latérale : place des boutons de la fenêtre, puis, selon les réglages,
/// précédent, suivant, recharger et Accueil.
struct SidebarTopBar: View {
    static let height = 32.0
    /// Place des boutons rouge, orange et vert de la fenêtre.
    static let windowButtonsWidth = 78.0

    let tab: BrowserTab?
    var showsNavigationButtons = true
    /// Action du bouton Accueil ; nil pour ne pas l'afficher.
    var goHome: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            Spacer(minLength: Self.windowButtonsWidth)
            NavigationButtons(tab: tab, showsHistoryButtons: showsNavigationButtons, goHome: goHome)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(SidebarIconButtonStyle())
        .frame(height: Self.height)
    }
}

/// Bouton-icône carré de la barre latérale, surligné au survol.
struct SidebarIconButtonStyle: ButtonStyle {
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
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered && isEnabled ? 0.1 : 0)),
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 0.85) : 0.3)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}
