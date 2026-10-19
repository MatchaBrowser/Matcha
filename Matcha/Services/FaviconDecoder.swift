import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A website icon decoded off the main thread: the image, reduced, and its look.
nonisolated struct DecodedFavicon: Sendable {
    let image: CGImage
    let tone: FaviconTone
}

/// Decoding of downloaded icons (audit W8), away from the main thread and only for bitmap formats: never PDF or SVG,
/// whose decoders are large, in the app's process (WebKit decodes the page's images in its own sandboxed process).
/// The sharpest image of an ICO file, reduced to `maximumPixels`. Pure type.
nonisolated enum FaviconDecoder {
    static let acceptedTypes: Set<String> = Set([UTType.png, .jpeg, .gif, .ico, .webP, .bmp, .tiff].map(\.identifier))
    /// Largest side kept: the sidebar shows icons at 16 to 32 points.
    static let maximumPixels = 128

    @concurrent
    static func decode(_ data: Data) async -> DecodedFavicon? {
        decodeNow(data)
    }

    static func decodeNow(_ data: Data) -> DecodedFavicon? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let type = CGImageSourceGetType(source) as String?, acceptedTypes.contains(type)
        else {
            return nil
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, sharpestIndex(in: source), thumbnailOptions),
              image.width > 0, image.height > 0
        else {
            return nil
        }
        return DecodedFavicon(image: image, tone: tone(of: image))
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

    /// Image with the most pixels among those of the file (an ICO holds several sizes).
    private static func sharpestIndex(in source: CGImageSource) -> Int {
        let sizes = (0 ..< CGImageSourceGetCount(source)).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            return width * height
        }
        return sizes.indices.max { sizes[$0] < sizes[$1] } ?? 0
    }
}
