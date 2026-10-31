import Foundation

/// Dimensions of the sidebar.
nonisolated enum SidebarMetrics {
    static let defaultWidth = 240.0
    static let widthRange = 180.0 ... 400.0

    /// Width brought back within the allowed limits.
    static func clampedWidth(_ width: Double) -> Double {
        min(max(width, widthRange.lowerBound), widthRange.upperBound)
    }
}
