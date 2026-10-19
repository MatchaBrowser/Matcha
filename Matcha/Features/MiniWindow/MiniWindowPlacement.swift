import CoreGraphics
import Foundation

/// Size and position of a new mini window (AppKit screen coordinates, origin at the bottom left), with no
/// dependency on the interface.
nonisolated enum MiniWindowPlacement {
    static let defaultSize = CGSize(width: 520, height: 680)
    static let minimumSize = CGSize(width: 360, height: 400)
    /// Margin kept from the edges of the screen's usable area.
    static let margin = 20.0
    /// Offset of a mini window opened while another one already is.
    static let cascadeOffset = 24.0
    /// `UserDefaults` key of the last size chosen with the mouse (“{520, 680}”).
    static let sizeKey = "miniWindowSize"

    /// Remembered size, if it is readable and at least equal to the minimum size.
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

    /// Frame of a mini window of size `size` in `visible` (usable area of the screen, minus the margin):
    /// - the size is reduced to fit the area, without going below the minimum size;
    /// - larger than the area: at the top left of the area;
    /// - offset by 24 pt to the right and down from `previous` (the last opened mini window), as long as
    ///   it fits in the area;
    /// - otherwise centered.
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
