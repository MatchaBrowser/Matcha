import SwiftUI

/// Couche de la barre de commande sur toute la fenêtre, sans fond : seul le panneau reçoit les clics.
/// Le panneau est centré sur la fenêtre, à 18 % de sa hauteur ; il apparaît en fondu et disparaît
/// sans animation, pour que deux champs d'adresse n'existent jamais en même temps.
struct CommandBarOverlay: View {
    static let maximumWidth = 640.0
    static let horizontalMargin = 24.0
    static let minimumTop = 52.0
    static let bottomMargin = 24.0

    let model: CommandBarModel
    let executor: CommandBarExecutor
    let theme: SpaceTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let top = max(Self.minimumTop, (geometry.size.height * 0.18).rounded())
            VStack(spacing: 0) {
                if model.isPresented {
                    CommandBarPanel(
                        model: model,
                        executor: executor,
                        theme: theme,
                        maxHeight: geometry.size.height - top - Self.bottomMargin,
                    )
                    .background { OutsideClickMonitor { model.dismiss() } }
                    .frame(maxWidth: Self.maximumWidth)
                    .padding(.horizontal, Self.horizontalMargin)
                    .padding(.top, top)
                    .transition(.asymmetric(insertion: insertion, removal: .identity))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            // Ouverture animée ; fermeture et changements de lignes sans animation.
            .animation(model.isPresented ? .easeOut(duration: 0.12) : nil, value: model.isPresented)
        }
    }

    private var insertion: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }
}
