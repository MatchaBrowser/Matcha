import CoreGraphics
import Foundation

/// Géométrie de l'aperçu dans la zone des pages (origine en haut à gauche) : panneau à 85 %, centré, et sa
/// barre juste au-dessus.
nonisolated struct PeekLayout: Equatable, Sendable {
    static let sizeRatio = 0.85
    static let minimumMargin = 12.0
    static let toolbarHeight = 28.0
    static let toolbarGap = 8.0
    static let center = CGPoint(x: 0.5, y: 0.5)

    let pane: CGRect
    let toolbar: CGRect

    init(container size: CGSize) {
        let topReserve = Self.minimumMargin + Self.toolbarHeight + Self.toolbarGap
        let width = max(0, min((size.width * Self.sizeRatio).rounded(), size.width - 2 * Self.minimumMargin))
        let height = max(0, min((size.height * Self.sizeRatio).rounded(), size.height - topReserve - Self.minimumMargin))
        let left = ((size.width - width) / 2).rounded()
        let top = max(((size.height - height) / 2).rounded(), topReserve)
        pane = CGRect(x: left, y: top, width: width, height: height)
        toolbar = CGRect(x: left, y: top - Self.toolbarGap - Self.toolbarHeight, width: width, height: Self.toolbarHeight)
    }

    /// `point` en fractions de `size`, bornées à 0…1, origine en haut à gauche ; le centre pour une taille nulle.
    static func fraction(of point: CGPoint, in size: CGSize, flipped: Bool) -> CGPoint {
        guard size.width > 0, size.height > 0 else {
            return center
        }
        let horizontal = point.x / size.width
        let vertical = flipped ? point.y / size.height : 1 - point.y / size.height
        return CGPoint(x: min(max(horizontal, 0), 1), y: min(max(vertical, 0), 1))
    }
}
