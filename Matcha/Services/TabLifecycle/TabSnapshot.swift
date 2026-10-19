import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Snapshot of a page before it is put to sleep (task 5.6), compressed as JPEG to weigh little in memory (a few tens of
/// kilobytes), with the address of the captured page (it never covers another page) and the width of the view in points
/// (it does not cover a page displayed at another width, with a different layout).
nonisolated struct TabSnapshot: Sendable {
    /// Maximum width of the kept image, in pixels: a Retina snapshot is reduced by about half.
    static let maximumPixelWidth = 1200
    /// JPEG quality: the snapshot is only shown for a moment, while the page reloads.
    static let jpegQuality = 0.7

    let data: Data
    let url: URL?
    /// Width of the captured view, in points.
    let pageWidth: Double

    /// Size of the image kept for a snapshot of `width` × `height` pixels: same aspect ratio, width at most
    /// `maximumWidth`, never enlarged, at least one pixel per side.
    static func pixelSize(width: Int, height: Int, maximumWidth: Int = maximumPixelWidth) -> (width: Int, height: Int) {
        guard width > maximumWidth, width > 0 else {
            return (max(width, 1), max(height, 1))
        }
        let scaledHeight = (Double(height) * Double(maximumWidth) / Double(width)).rounded()
        return (maximumWidth, max(Int(scaledHeight), 1))
    }

    /// `jpegData` off the main thread.
    @concurrent
    static func encode(_ image: CGImage) async -> Data? {
        jpegData(from: image)
    }

    /// Image scaled down (`pixelSize`) then compressed as JPEG; nil if the image cannot be drawn or encoded.
    static func jpegData(from image: CGImage, maximumWidth: Int = maximumPixelWidth, quality: Double = jpegQuality) -> Data? {
        let size = pixelSize(width: image.width, height: image.height, maximumWidth: maximumWidth)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: size.width,
                  height: size.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
              )
        else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let scaled = context.makeImage() else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
