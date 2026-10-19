import SwiftUI

/// Background of the window and of the sidebar, in the colors of the Space's theme.
/// A change of theme (or of Space) fades.
struct SpaceBackground: View {
    let theme: SpaceTheme

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(colors: theme.swiftUIColors(for: colorScheme), startPoint: theme.startPoint, endPoint: theme.endPoint)
                .id(theme)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.4), value: theme)
        .ignoresSafeArea()
    }
}
