import SwiftUI

/// Result row of the command bar: icon, title, subtitle, then a tab's capsules and ⏎ on the selected row. Hovering
/// only highlights; a click runs.
struct CommandBarRowView: View {
    let row: CommandRow
    let isSelected: Bool
    /// Name of the engine of the current opening (“Search …”).
    let searchEngineName: String
    /// Color of the displayed Space, which tints the selected row.
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

    /// Displayed subtitle: the row's address, or the engine for a search.
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
