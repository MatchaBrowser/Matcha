import CoreGraphics

/// A website's icon, with its look (to display it legibly on the sidebar).
@MainActor
final class Favicon {
    let image: CGImage
    let tone: FaviconTone

    init(image: CGImage, tone: FaviconTone) {
        self.image = image
        self.tone = tone
    }

    /// Icon decoded off the main thread (`FaviconDecoder`).
    convenience init(decoded: DecodedFavicon) {
        self.init(image: decoded.image, tone: decoded.tone)
    }
}
