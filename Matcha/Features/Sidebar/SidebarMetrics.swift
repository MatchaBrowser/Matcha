import Foundation

/// Dimensions de la barre latérale.
nonisolated enum SidebarMetrics {
    static let defaultWidth = 240.0
    static let widthRange = 180.0 ... 400.0

    /// Largeur ramenée dans les limites autorisées.
    static func clampedWidth(_ width: Double) -> Double {
        min(max(width, widthRange.lowerBound), widthRange.upperBound)
    }
}
