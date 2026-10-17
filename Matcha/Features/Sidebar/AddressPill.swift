import SwiftUI

/// Pastille d'adresse : le domaine de l'onglet affiché. Un clic (ou ⌘L) ouvre la barre de commande
/// sur l'adresse complète.
struct AddressPill: View {
    let tabManager: TabManager
    let edit: () -> Void

    @State private var isHovered = false

    private var tab: BrowserTab? {
        tabManager.selectedTab
    }

    var body: some View {
        Button(action: edit) {
            HStack(spacing: 8) {
                leadingIcon
                text
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(isHovered ? 0.10 : 0.07)),
            )
            .overlay(alignment: .bottomLeading) { progressLine }
            .contentShape(.rect)
        }
        // Le conteneur (barre au-dessus de la page) impose un style de bouton-icône.
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text("Edit Address", comment: "Tooltip of the address pill"))
        .accessibilityLabel(Text("Address", comment: "Accessibility label of the address pill"))
        .accessibilityValue(Text(verbatim: AddressDisplay.short(for: tab?.url)))
        .accessibilityIdentifier("addressPill")
    }

    /// Icône du site, ou une loupe sans page.
    @ViewBuilder private var leadingIcon: some View {
        if let tab, tab.url != nil {
            FaviconView(tab: tab)
        } else {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        }
    }

    /// Domaine affiché, ou l'invite de saisie sans page.
    @ViewBuilder private var text: some View {
        if let url = tab?.url {
            Text(verbatim: AddressDisplay.short(for: url))
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text("Search or enter address")
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
    }

    /// Fine barre de chargement en bas de la pastille.
    @ViewBuilder private var progressLine: some View {
        if let tab, tab.isLoading {
            GeometryReader { geometry in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(geometry.size.width * tab.progress, 8), height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 6)
        }
    }
}
