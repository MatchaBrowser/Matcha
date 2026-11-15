import CoreGraphics

/// Where the native list of a login field goes over the page (`VAULT.md` § 8.1), in the web view's points (origin at
/// the top left): under the field, or above it when it fits there and not below; at least `minimumWidth` wide, kept
/// inside the page. Pure type.
nonisolated enum VaultSuggestionPlacement {
    static let minimumWidth: CGFloat = 260
    static let gap: CGFloat = 4
    static let margin: CGFloat = 8

    /// The field's box in a web view of `size`; nil when it is out of sight. The viewport's CSS width maps to the view's
    /// width: the page's zoom is in their ratio.
    static func fieldBox(_ place: VaultFieldPlace, in size: CGSize) -> CGRect? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        let scale = size.width / place.viewportWidth
        let box = CGRect(x: place.left * scale, y: place.top * scale, width: place.width * scale, height: place.height * scale)
        guard box.maxY > 0, box.minY < size.height, box.maxX > 0, box.minX < size.width else {
            return nil
        }
        return box
    }

    /// The list's frame, `height` points high, for a field at `field`.
    static func listFrame(for field: CGRect, height: CGFloat, in size: CGSize) -> CGRect {
        let width = max(min(max(field.width, minimumWidth), size.width - 2 * margin), 0)
        let left = max(min(field.minX, size.width - margin - width), margin)
        let below = field.maxY + gap
        let above = field.minY - gap - height
        let top = below + height <= size.height || above < 0 ? below : above
        return CGRect(x: left, y: top, width: width, height: height)
    }
}
