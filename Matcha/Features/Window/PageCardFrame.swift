import SwiftUI

extension View {
    /// Frame of a page's card, in a browser window and in a mini window (review CO4): background, rounded corners and a
    /// hairline border, in the accent color when `isMarked` (active pane of a split). The background stays out of the
    /// hidden title bar's area: clipped on screen, it would still take the clicks of the margin above.
    func pageCardFrame(cornerRadius: Double, isMarked: Bool = false) -> some View {
        background(.background, ignoresSafeAreaEdges: [])
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isMarked ? AnyShapeStyle(Color.accentColor.opacity(0.7)) : AnyShapeStyle(.hairline),
                        lineWidth: isMarked ? 2 : 1,
                    )
                    .allowsHitTesting(false)
            }
    }

    /// Shadow of an opaque card with rounded corners (page card, peek), cast by a shape of the same outline placed
    /// behind it. A `shadow` on the card itself lands on a layer that contains the web view, without a path: Core
    /// Animation then renders the whole page off screen at every frame to find its outline, and videos flicker
    /// (YouTube, Twitch).
    func cardShadow(cornerRadius: Double, color: Color, radius: Double, offsetY: Double) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.background)
                .shadow(color: color, radius: radius, y: offsetY)
                .allowsHitTesting(false)
        }
    }
}
