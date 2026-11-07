import Foundation

/// Width of the notes panel (task 12.3), shared by the windows like the sidebar's. Pure type.
nonisolated enum NotesPanelMetrics {
    static let defaultWidth = 340.0
    static let minimumWidth = 260.0
    static let maximumWidth = 640.0
    /// Settings key of the saved width.
    static let widthKey = "notesPanelWidth"

    static func clampedWidth(_ width: Double) -> Double {
        width.isFinite ? min(max(width, minimumWidth), maximumWidth) : defaultWidth
    }
}
