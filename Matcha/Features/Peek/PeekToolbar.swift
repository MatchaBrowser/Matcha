import SwiftUI

/// Floating bar above the peek: site and zoom of its page on the left, “Open as Tab” and × on the right.
struct PeekToolbar: View {
    let page: BrowserTab
    let tabManager: TabManager

    var body: some View {
        HStack(spacing: 6) {
            address
            ZoomBadge(page: page, siteZooms: tabManager.siteZooms, style: .floating)
            Spacer(minLength: 8)
            Button { PeekActions.openAsTab(in: tabManager) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help(openAsTabTitle)
            .accessibilityLabel(openAsTabTitle)
            .accessibilityIdentifier("peekOpenAsTabButton")
            // ⎋ when the page does not have keyboard focus; otherwise the page goes first (PeekWebContainer). With
            // the find bar open, ⎋ is left to its field (which closes the bar): the shortcut would otherwise take
            // precedence and close the peek.
            Button { PeekActions.close(in: tabManager) } label: {
                Image(systemName: "xmark")
            }
            .keyboardShortcut(page.find.isPresented ? nil : .cancelAction)
            .help(Text(PeekActions.closeTitle))
            .accessibilityLabel(Text(PeekActions.closeTitle))
            .accessibilityIdentifier("peekCloseButton")
        }
        .buttonStyle(PeekRoundButtonStyle())
        .animatesZoomBadge(of: page)
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
        // Static text: on macOS, a plain group does not expose its value (the address).
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(Text("Address", comment: "Accessibility label of the address pill"))
        .accessibilityValue(Text(verbatim: shortAddress))
        .accessibilityIdentifier("peekAddress")
    }
}

/// Round button of the peek's bar, highlighted on hover.
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
