import SwiftUI

/// Toolbar of a mini window: close, back (if there is a previous page), the address (a click edits it, like ⌘L)
/// and the page's zoom, an empty area that moves the window, then “Open in ‹Space›”.
struct MiniWindowToolbar: View {
    static let height = 40.0

    let tab: BrowserTab
    /// Space targeted by the button (and by ⇧⌘O); follows the Space displayed by the main window.
    let target: SpaceSession
    /// Per-site zoom of the main session, reset to 100 % by a click on the zoom badge (task 5.4).
    let siteZooms: SiteZoomStore?
    let close: () -> Void
    let editAddress: () -> Void
    let openInSpace: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button("Close Mini Window", systemImage: "xmark", action: close)
                .help("Close Mini Window")
                .accessibilityIdentifier("miniWindowClose")
            if tab.canGoBack {
                Button("Back", systemImage: "arrow.left") { tab.goBack() }
            }
            AddressPill(tab: tab, edit: editAddress)
                .frame(minWidth: 120, maxWidth: 280)
            ZoomBadge(page: tab, siteZooms: siteZooms)
            TranslateButton(page: tab)
            // The window's background shows here: dragging this area moves the window.
            Spacer(minLength: 12)
            openButton
        }
        .labelStyle(.iconOnly)
        .buttonStyle(SidebarIconButtonStyle())
        .animatesZoomBadge(of: tab)
        .padding(.horizontal, 8)
        .frame(height: Self.height)
    }

    /// “Open in ‹Space›”, with the Space's icon (symbol or emoji); the name is truncated before the button
    /// shrinks.
    private var openButton: some View {
        Button(action: openInSpace) {
            HStack(spacing: 6) {
                SidebarIconView(icon: target.icon, defaultSymbol: SidebarIcon.defaultSpaceSymbol, size: 12, weight: .medium)
                Text("Open in \(target.record.name)", comment: "Mini window button; %@ is the name of the Space")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .frame(maxWidth: 190)
            .background(RoundedRectangle(cornerRadius: 6).fill(.subtleFill))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(tab.url == nil)
        .accessibilityLabel(Text("Open in Space"))
        .accessibilityValue(Text(verbatim: target.record.name))
        .accessibilityIdentifier("miniWindowOpenInSpace")
    }
}
