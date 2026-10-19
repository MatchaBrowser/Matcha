import CoreGraphics
import Foundation

/// Size and position of a sign-in window (task 5.8), in AppKit screen coordinates (origin at the bottom left),
/// without UI dependency.
nonisolated enum PopupWindowPlacement {
    /// Page size when the page gives only one of the two dimensions.
    static let defaultPageSize = CGSize(width: 600, height: 600)
    /// Smallest page: so that a tiny window (1 × 1) stays usable.
    static let minimumPageSize = CGSize(width: 320, height: 300)

    /// Page size: the requested one (the missing dimension takes the default value), at least the minimum size,
    /// rounded to the point.
    static func pageSize(for features: PopupWindowFeatures) -> CGSize {
        CGSize(
            width: max(minimumPageSize.width, (features.width ?? defaultPageSize.width).rounded()),
            height: max(minimumPageSize.height, (features.height ?? defaultPageSize.height).rounded()),
        )
    }

    /// Frame of a window of size `size` (title bar included) in `visible`, the usable area of the screen:
    /// - the size is reduced to fit the area;
    /// - the window is centered on `opener`, the frame of the originating window, or failing that on the area;
    /// - then slid to fit entirely within the area.
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
