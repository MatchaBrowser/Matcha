import SwiftUI

/// Barre flottante au-dessus de l'aperçu : site à gauche, « Ouvrir en onglet » et × à droite.
struct PeekToolbar: View {
    let page: BrowserTab
    let tabManager: TabManager

    var body: some View {
        HStack(spacing: 6) {
            address
            Spacer(minLength: 8)
            Button { PeekActions.openAsTab(in: tabManager) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help(openAsTabTitle)
            .accessibilityLabel(openAsTabTitle)
            .accessibilityIdentifier("peekOpenAsTabButton")
            // ⎋ quand la page n'a pas le clavier ; sinon la page passe d'abord (PeekWebContainer). Barre de recherche
            // ouverte, ⎋ revient à son champ (qui la ferme) : le raccourci passerait avant lui et fermerait l'aperçu.
            Button { PeekActions.close(in: tabManager) } label: {
                Image(systemName: "xmark")
            }
            .keyboardShortcut(page.find.isPresented ? nil : .cancelAction)
            .help(Text(PeekActions.closeTitle))
            .accessibilityLabel(Text(PeekActions.closeTitle))
            .accessibilityIdentifier("peekCloseButton")
        }
        .buttonStyle(PeekRoundButtonStyle())
    }

    private var openAsTabTitle: Text {
        Text("Open as Tab", comment: "Peek: button that turns the preview into a tab, without reloading the page")
    }

    private var shortAddress: String {
        AddressDisplay.short(for: page.url)
    }

    private var address: some View {
        HStack(spacing: 6) {
            FaviconView(tab: page, size: 14)
            Text(verbatim: shortAddress)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if page.isLoading {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: PeekLayout.toolbarHeight)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1) }
        .contentShape(Capsule())
        .help(Text(verbatim: page.url?.absoluteString ?? ""))
        // Texte statique : sous macOS, un simple groupe n'expose pas sa valeur (l'adresse).
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(Text("Address", comment: "Accessibility label of the address pill"))
        .accessibilityValue(Text(verbatim: shortAddress))
        .accessibilityIdentifier("peekAddress")
    }
}

/// Bouton rond de la barre de l'aperçu, surligné au survol.
private struct PeekRoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PeekRoundButton(configuration: configuration)
    }
}

private struct PeekRoundButton: View {
    let configuration: ButtonStyleConfiguration

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .frame(width: PeekLayout.toolbarHeight, height: PeekLayout.toolbarHeight)
            .background {
                ZStack {
                    Circle().fill(.regularMaterial)
                    Circle().fill(Color.primary.opacity(isHovered ? 0.1 : 0))
                }
            }
            .overlay { Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Circle())
            .onHover { isHovered = $0 }
    }
}
