import SwiftUI

/// Moitié de panneau colorée pendant un glisser : l'onglet lâché ici se placera de ce côté du panneau.
struct SplitDropHighlight: View {
    let target: SplitDropTarget?
    /// Largeurs des panneaux affichés, de gauche à droite.
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
