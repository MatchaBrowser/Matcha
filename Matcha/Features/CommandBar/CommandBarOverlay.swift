import SwiftUI

/// Couche de la barre de commande sur toute la fenêtre, sans fond : seul le panneau reçoit les clics.
/// Le panneau est placé selon `placement` (centré à 18 % de la hauteur d'une fenêtre de navigation, sous la barre
/// d'outils d'une mini-fenêtre) ; il apparaît en fondu et disparaît sans animation, pour que deux champs
/// d'adresse n'existent jamais en même temps.
struct CommandBarOverlay: View {
    let model: any CommandBarPanelModel
    let submit: (CommandRow.ID?) -> Void
    let cancel: () -> Void
    let theme: SpaceTheme
    var placement = CommandBarPlacement.window

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let top = placement.top(inHeight: geometry.size.height)
            VStack(spacing: 0) {
                if model.isPresented {
                    CommandBarPanel(
                        model: model,
                        submit: submit,
                        cancel: cancel,
                        theme: theme,
                        maxHeight: geometry.size.height - top - placement.bottomMargin,
                    )
                    .background { OutsideClickMonitor { model.dismiss() } }
                    .frame(maxWidth: placement.maximumWidth)
                    .padding(.horizontal, placement.horizontalMargin)
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
