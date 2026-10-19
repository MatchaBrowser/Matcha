import SwiftUI

/// Address pill: the domain of the displayed tab (or of the pane, in the bar above the page). A click (or ⌘L)
/// opens the command bar on the full address.
struct AddressPill: View {
    let tab: BrowserTab?
    let edit: () -> Void

    @State private var isHovered = false

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
        // The container (bar above the page) imposes an icon-button style.
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text("Edit Address", comment: "Tooltip of the address pill"))
        .accessibilityLabel(Text("Address", comment: "Accessibility label of the address pill"))
        .accessibilityValue(Text(verbatim: AddressDisplay.short(for: tab?.url)))
        .accessibilityIdentifier("addressPill")
    }

    /// The site's icon, or a magnifying glass without a page.
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

    /// Displayed domain, or the input prompt without a page.
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

    /// Thin loading bar at the bottom of the pill.
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
