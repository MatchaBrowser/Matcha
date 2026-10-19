import CoreGraphics

/// Size of a browser window at its first opening (audit H5): 85 % of the screen's free area, at most 1440 × 960
/// points, at least the window's minimum (700 × 450). Pure type.
nonisolated enum BrowserWindowSize {
    static let maximum = CGSize(width: 1440, height: 960)
    static let minimum = CGSize(width: 700, height: 450)

    static func defaultSize(visible: CGSize) -> CGSize {
        CGSize(
            width: max(minimum.width, min(maximum.width, (visible.width * 0.85).rounded())),
            height: max(minimum.height, min(maximum.height, (visible.height * 0.85).rounded())),
        )
    }
}
