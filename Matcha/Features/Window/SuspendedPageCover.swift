import SwiftUI

/// Snapshot of a tab woken from sleep (task 5.6), placed over its page while it reloads: at the page's width, pinned to
/// the top. Nothing if the page no longer has the snapshot's width (window resized, pane of a split): its layout has
/// changed, the snapshot would no longer look like it. It takes neither clicks nor keyboard: the page underneath stays
/// usable.
struct SuspendedPageCover: View {
    /// Tolerated width difference, as a fraction of the page's width.
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

    /// True if a snapshot of a page `pageWidth` points wide looks like the page displayed on `width` points.
    nonisolated static func fits(pageWidth: Double, in width: Double) -> Bool {
        width > 0 && abs(pageWidth - width) <= width * widthTolerance
    }
}
