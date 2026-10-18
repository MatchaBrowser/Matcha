import SwiftUI

/// Capture d'un onglet sorti de veille (tâche 5.6), posée sur sa page le temps du rechargement : à la largeur de la
/// page, calée en haut. Rien si la page n'a plus la largeur de la capture (fenêtre redimensionnée, panneau d'un split) :
/// sa mise en page a changé, la capture ne lui ressemblerait plus. Elle ne prend ni clic ni clavier : la page dessous
/// reste utilisable.
struct SuspendedPageCover: View {
    /// Écart de largeur toléré, en fraction de la largeur de la page.
    nonisolated static let widthTolerance = 0.1

    let cover: TabCover

    var body: some View {
        GeometryReader { proxy in
            if Self.fits(pageWidth: cover.pageWidth, in: proxy.size.width) {
                let size = cover.image.size
                let height = size.width > 0 ? proxy.size.width * size.height / size.width : proxy.size.height
                Image(nsImage: cover.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: proxy.size.width, height: height)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .clipped()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Vrai si une capture d'une page large de `pageWidth` points ressemble à la page affichée sur `width` points.
    nonisolated static func fits(pageWidth: Double, in width: Double) -> Bool {
        width > 0 && abs(pageWidth - width) <= width * widthTolerance
    }
}
