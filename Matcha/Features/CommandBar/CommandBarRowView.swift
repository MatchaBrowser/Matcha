import SwiftUI

/// Ligne de résultat de la barre de commande : icône, titre, sous-titre, puis les capsules d'un
/// onglet et ⏎ sur la ligne sélectionnée. Le survol ne fait que surligner ; un clic exécute.
struct CommandBarRowView: View {
    let row: CommandRow
    let isSelected: Bool
    /// Nom du moteur de l'ouverture en cours (« Rechercher sur … »).
    let searchEngineName: String
    /// Couleur du Space affiché, qui teinte la ligne sélectionnée.
    let tint: Color
    let icons: CommandRowIcons
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 16, height: 16)
            Text(verbatim: row.title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if let subtitle {
                Text(verbatim: subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background { background }
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.title))
        .accessibilityValue(Text(verbatim: subtitle ?? ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, action)
        .accessibilityIdentifier("commandBarRow")
    }

    /// Sous-titre affiché : l'adresse de la ligne, ou le moteur pour une recherche.
    private var subtitle: String? {
        switch row.style {
        case .search, .searchAlternative:
            String(
                localized: "Search \(searchEngineName)",
                comment: "Subtitle of search rows in the command bar; %@ is the search engine name",
            )
        case .suggestion, .action:
            nil
        case .openAddress, .tab, .history:
            row.subtitle
        }
    }

    @ViewBuilder private var icon: some View {
        switch row.style {
        case .search, .searchAlternative, .suggestion:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        case let .tab(reference, _, _):
            if let tab = icons.tab(reference) {
                FaviconView(tab: tab)
            } else {
                siteIcon
            }
        case .openAddress, .history:
            siteIcon
        case let .action(action):
            Image(systemName: action.symbolName)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var siteIcon: some View {
        CachedSiteIcon(host: row.url?.host(), service: icons.faviconService)
    }

    @ViewBuilder private var accessory: some View {
        if case let .tab(_, _, spaceName) = row.style {
            if let spaceName {
                capsule(Text(verbatim: spaceName))
            }
            capsule(Text("Switch to Tab", comment: "Hint on tab rows of the command bar"))
        }
        if isSelected {
            Image(systemName: "return")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func capsule(_ text: Text) -> some View {
        text
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        if isSelected {
            shape.fill(Color.primary.opacity(0.06))
                .overlay { shape.fill(tint.opacity(0.30)) }
        } else if isHovered {
            shape.fill(Color.primary.opacity(0.05))
        }
    }
}
