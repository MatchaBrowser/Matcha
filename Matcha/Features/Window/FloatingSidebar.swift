import SwiftUI

/// Sidebar displayed over the page when it is hidden: card with a theme background, with a shadow.
struct FloatingSidebar<Content: View>: View {
    let theme: SpaceTheme
    let width: Double
    let onHover: (Bool) -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: width)
            .background { SpaceBackground(theme: theme) }
            .clipShape(.rect(cornerRadius: BrowserWindowView.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: BrowserWindowView.cardCornerRadius)
                    .strokeBorder(.hairline, lineWidth: 1)
            }
            .onHover(perform: onHover)
            .shadow(color: .black.opacity(0.3), radius: 12, x: 2)
            .padding(.vertical, BrowserWindowView.cardMargin)
    }
}
