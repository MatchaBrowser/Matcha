import SwiftUI

/// Address pill: the domain of the displayed tab (or of the pane, in the bar above the page). A click (or ⌘L)
/// opens the command bar on the full address. At its end, the page's security (audit W5): a padlock that shows the
/// certificate, or “Not Secure”.
struct AddressPill: View {
    let tab: BrowserTab?
    let edit: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: edit) {
                HStack(spacing: 8) {
                    leadingIcon
                    text
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10)
                .frame(height: 32)
                .contentShape(.rect)
            }
            // The container (bar above the page) imposes an icon-button style.
            .buttonStyle(.plain)
            .help(Text("Edit Address", comment: "Tooltip of the address pill"))
            .accessibilityLabel(Text("Address", comment: "Accessibility label of the address pill"))
            .accessibilityValue(Text(verbatim: AddressDisplay.short(for: tab?.displayedURL)))
            .accessibilityIdentifier("addressPill")
            if let tab {
                PageSecurityIndicator(page: tab)
                    .font(.subheadline)
            }
        }
        .padding(.trailing, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(isHovered ? 0.10 : 0.07)),
        )
        .overlay(alignment: .bottomLeading) { progressLine }
        .onHover { isHovered = $0 }
    }

    /// The site's icon, or a magnifying glass without a page.
    @ViewBuilder private var leadingIcon: some View {
        if let tab, tab.displayedURL != nil {
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
        if let url = tab?.displayedURL {
            Text(verbatim: AddressDisplay.short(for: url))
                .lineLimit(1)
                .truncationMode(.middle)
                // The domain goes first; “Not Secure” gives way.
                .layoutPriority(1)
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
