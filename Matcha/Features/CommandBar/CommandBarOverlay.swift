import SwiftUI

/// Command bar layer over the whole window, with no background: only the panel receives clicks.
/// The panel is placed according to `placement` (centered at 18% of the height of a browser window, below the
/// toolbar of a mini window); it fades in and disappears without animation, so that two address fields never exist
/// at the same time.
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
            // Animated opening; closing and row changes without animation.
            .animation(model.isPresented ? .easeOut(duration: 0.12) : nil, value: model.isPresented)
        }
    }

    private var insertion: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }
}
