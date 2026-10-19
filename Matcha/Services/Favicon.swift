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

    /// Icon read from the downloaded data; nil if it is not a valid image.
    convenience init?(data: Data) {
        guard let image = NSImage(data: data), image.isValid, image.size.width > 0 else {
            return nil
        }
        self.init(image: image, tone: Self.tone(of: image))
    }

    /// Look of the image, analyzed on a 32 × 32 pixel reduction.
    static func tone(of image: NSImage) -> FaviconTone {
        let side = 32
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: side * 4,
            bitsPerPixel: 32,
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return .neutral
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.bitmapData else {
            return .neutral
        }
        return FaviconTone.analyze(rgba: Array(UnsafeBufferPointer(start: data, count: side * side * 4)))
    }
}
