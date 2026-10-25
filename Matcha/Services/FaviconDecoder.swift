import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A website icon decoded off the main thread: the image, reduced, and its look.
nonisolated struct DecodedFavicon: Sendable {
    let image: CGImage
    let tone: FaviconTone
}

/// Decoding of downloaded icons (audit W8), away from the main thread, by the bounded decoder (review TR3): bitmap
/// formats only, never PDF or SVG; of an ICO file, the smallest image of at least `maximumPixels`, reduced to that size.
/// Pure type.
nonisolated enum FaviconDecoder {
    /// Largest side kept: the sidebar shows icons at 16 to 32 points.
    static let maximumPixels = BoundedImageDecoder.Limits.favicon.maximumSide

    @concurrent
    static func decode(_ data: Data) async -> DecodedFavicon? {
        decodeNow(data)
    }

    static func decodeNow(_ data: Data) -> DecodedFavicon? {
        BoundedImageDecoder.decode(data, limits: .favicon).map { DecodedFavicon(image: $0, tone: tone(of: $0)) }
    }

    /// Look of the image, analyzed on a 32 × 32 pixel reduction.
    static func tone(of image: CGImage) -> FaviconTone {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? FaviconTone.analyze(rgba: pixels) : .neutral
    }
}
