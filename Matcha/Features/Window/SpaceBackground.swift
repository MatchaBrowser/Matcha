import SwiftUI

/// Fond de la fenêtre et de la barre latérale, aux couleurs du thème du Space.
/// Un changement de thème (ou de Space) se fait en fondu.
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
