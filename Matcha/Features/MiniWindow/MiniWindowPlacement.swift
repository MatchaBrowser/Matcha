import CoreGraphics
import Foundation

/// Taille et place d'une nouvelle mini-fenêtre (coordonnées d'écran d'AppKit, origine en bas à gauche), sans
/// dépendance à l'interface.
nonisolated enum MiniWindowPlacement {
    static let defaultSize = CGSize(width: 520, height: 680)
    static let minimumSize = CGSize(width: 360, height: 400)
    /// Marge gardée avec les bords de la zone utile de l'écran.
    static let margin = 20.0
    /// Décalage d'une mini-fenêtre ouverte alors qu'une autre l'est déjà.
    static let cascadeOffset = 24.0
    /// Clé `UserDefaults` de la dernière taille choisie à la souris (« {520, 680} »).
    static let sizeKey = "miniWindowSize"

    /// Taille retenue, si elle est lisible et au moins égale à la taille minimale.
    static func storedSize(_ text: String?) -> CGSize? {
        guard let text, !text.isEmpty else {
            return nil
        }
        let size = NSSizeFromString(text)
        guard size.width >= minimumSize.width, size.height >= minimumSize.height else {
            return nil
        }
        return size
    }

    /// Cadre d'une mini-fenêtre de taille `size` dans `visible` (zone utile de l'écran, moins la marge) :
    /// - la taille est ramenée à la zone, sans descendre sous la taille minimale ;
    /// - plus grande que la zone : en haut à gauche de la zone ;
    /// - décalée de 24 pt vers la droite et le bas depuis `previous` (la dernière mini-fenêtre ouverte), tant
    ///   qu'elle tient dans la zone ;
    /// - sinon centrée.
    static func frame(size requested: CGSize, in visible: CGRect, after previous: CGRect?) -> CGRect {
        let available = visible.insetBy(dx: margin, dy: margin)
        let size = CGSize(
            width: max(minimumSize.width, min(requested.width, available.width)),
            height: max(minimumSize.height, min(requested.height, available.height)),
        )
        guard size.width <= available.width, size.height <= available.height else {
            return CGRect(x: available.minX, y: available.maxY - size.height, width: size.width, height: size.height)
        }
        if let previous {
            let cascaded = CGRect(
                x: previous.minX + cascadeOffset,
                y: previous.maxY - cascadeOffset - size.height,
                width: size.width,
                height: size.height,
            )
            if available.contains(cascaded) {
                return cascaded
            }
        }
        return CGRect(
            x: (available.midX - size.width / 2).rounded(),
            y: (available.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height,
        )
    }
}
