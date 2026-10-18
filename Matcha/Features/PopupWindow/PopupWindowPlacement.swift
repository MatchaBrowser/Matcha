import CoreGraphics
import Foundation

/// Taille et place d'une fenêtre de connexion (tâche 5.8), en coordonnées d'écran d'AppKit (origine en bas à gauche),
/// sans dépendance à l'interface.
nonisolated enum PopupWindowPlacement {
    /// Taille de la page quand la page ne donne qu'une des deux dimensions.
    static let defaultPageSize = CGSize(width: 600, height: 600)
    /// Plus petite page : une fenêtre minuscule (1 × 1) resterait utilisable.
    static let minimumPageSize = CGSize(width: 320, height: 300)

    /// Taille de la page : celle demandée (la dimension absente prend la valeur par défaut), au moins la taille
    /// minimale, arrondie au point.
    static func pageSize(for features: PopupWindowFeatures) -> CGSize {
        CGSize(
            width: max(minimumPageSize.width, (features.width ?? defaultPageSize.width).rounded()),
            height: max(minimumPageSize.height, (features.height ?? defaultPageSize.height).rounded()),
        )
    }

    /// Cadre d'une fenêtre de taille `size` (barre de titre comprise) dans `visible`, la zone utile de l'écran :
    /// - la taille est ramenée à la zone ;
    /// - la fenêtre est centrée sur `opener`, le cadre de la fenêtre d'origine, ou à défaut sur la zone ;
    /// - puis glissée pour tenir entièrement dans la zone.
    static func frame(size requested: CGSize, opener: CGRect?, in visible: CGRect) -> CGRect {
        let size = CGSize(width: min(requested.width, visible.width), height: min(requested.height, visible.height))
        let center = opener.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: visible.midX, y: visible.midY)
        let left = (center.x - size.width / 2).rounded()
        let bottom = (center.y - size.height / 2).rounded()
        return CGRect(
            x: min(max(left, visible.minX), visible.maxX - size.width),
            y: min(max(bottom, visible.minY), visible.maxY - size.height),
            width: size.width,
            height: size.height,
        )
    }
}
