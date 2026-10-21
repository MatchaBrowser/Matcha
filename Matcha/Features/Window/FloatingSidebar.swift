import SwiftUI

/// Sidebar displayed over the page when it is hidden: card with a theme background, with a shadow. As in Arc, its
/// content stays where the visible sidebar puts it, and the window's buttons, which AppKit keeps in place (it puts
/// them back at each layout), end up inside the card.
struct FloatingSidebar<Content: View>: View {
    /// Gap between the card and the window's edges: small, so that the window's buttons (9 pt from the edges) keep
    /// some room around them in the card.
    static var inset: Double {
        2
    }

    /// Concentric with the content card, whose corner has `BrowserWindowView.cardCornerRadius` at `cardMargin`.
    static var cornerRadius: Double {
        BrowserWindowView.cardCornerRadius + BrowserWindowView.cardMargin - inset
    }

    let theme: SpaceTheme
    let width: Double
    let onHover: (Bool) -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        let card = RoundedRectangle(cornerRadius: Self.cornerRadius)
        content()
            // Laid out over the whole height and width, like the visible sidebar; the card cuts the edges.
            .padding([.leading, .top, .bottom], -Self.inset)
            .frame(width: width - Self.inset)
            .background {
                // Like the window's background: the top strip and the empty areas move the window.
                SpaceBackground(theme: theme)
                    .gesture(WindowDragGesture())
                    .allowsWindowActivationEvents(true)
                    .overlay(alignment: .top) {
                        TitleBarArea()
                            .frame(height: SidebarTopBar.height - Self.inset)
                    }
            }
            .clipShape(card)
            .overlay {
                card.strokeBorder(.hairline, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .onHover(perform: onHover)
            .shadow(color: .black.opacity(0.3), radius: 12, x: 2)
            .padding([.leading, .top, .bottom], Self.inset)
    }
}
