import SwiftUI

/// Half of a pane colored during a drag: the tab dropped here will be placed on this side of the pane.
struct SplitDropHighlight: View {
    let target: SplitDropTarget?
    /// Widths of the displayed panes, from left to right.
    let widths: [Double]

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let target, widths.indices.contains(target.paneIndex) {
                let width = widths[target.paneIndex]
                let origin = SplitGeometry.paneOrigins(widths: widths)[target.paneIndex]
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
                    }
                    .padding(6)
                    .frame(width: width / 2)
                    .frame(maxHeight: .infinity)
                    .offset(x: target.side == .leading ? origin : origin + width / 2)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.12), value: target)
    }
}
