import AppKit

/// A website's icon, with its look (to display it legibly on the sidebar).
@MainActor
final class Favicon {
    let image: NSImage
    let tone: FaviconTone

    init(image: NSImage, tone: FaviconTone) {
        self.image = image
        self.tone = tone
    }

    /// Icon decoded off the main thread (`FaviconDecoder`).
    convenience init(decoded: DecodedFavicon) {
        self.init(image: NSImage(cgImage: decoded.image, size: .zero), tone: decoded.tone)
    }

    /// Look of `image`, analyzed on a 32 × 32 pixel reduction.
    static func tone(of image: NSImage) -> FaviconTone {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .neutral
        }
        return FaviconDecoder.tone(of: cgImage)
    }
}
