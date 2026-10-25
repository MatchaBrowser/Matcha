import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Images from outside decoded with bounds (review TR3), in the app's process: only the bitmap formats of `Limits`,
/// never PDF or SVG, whose decoders are large; the size the file announces is checked before anything is decoded, so
/// that a small file declaring a huge image (1 MB of PNG for 20 000 × 20 000 pixels, 1.6 GB once decoded) never is;
/// the image is reduced while decoding, and turned upright. Pure type.
nonisolated enum BoundedImageDecoder {
    struct Limits: Sendable {
        /// Accepted types (`UTType` identifiers).
        let types: Set<String>
        /// Largest image of the file that may be decoded, in pixels (width × height).
        let maximumSourcePixels: Int
        /// Largest side of the decoded image.
        let maximumSide: Int

        /// Website icons (audit W8): their sharpest useful size, 128 pixels.
        static let favicon = Limits(
            types: Set([UTType.png, .jpeg, .gif, .ico, .webP].map(\.identifier)),
            maximumSourcePixels: 1024 * 1024,
            maximumSide: 128,
        )
        /// The account's avatar received from sync: an image of 256 pixels made by Matcha.
        static let avatar = Limits(types: Set([UTType.png, .jpeg].map(\.identifier)), maximumSourcePixels: 1024 * 1024, maximumSide: 256)
        /// A photo chosen on this Mac for the avatar, cropped and reduced afterwards.
        static let photo = Limits(
            types: Set([UTType.png, .jpeg, .heic, .heif, .tiff, .gif, .webP, .bmp].map(\.identifier)),
            maximumSourcePixels: 100_000_000,
            maximumSide: 1024,
        )
    }

    static func decode(_ data: Data, limits: Limits) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
            .flatMap { decode($0, limits: limits) }
    }

    static func decode(contentsOf url: URL, limits: Limits) -> CGImage? {
        CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary).flatMap { decode($0, limits: limits) }
    }

    /// Image to decode among `sizes` (a file such as an ICO holds several): the smallest one whose sides both reach
    /// `side`, otherwise the largest; never one beyond `maximumPixels`. Nil if none can be decoded.
    static func index(among sizes: [(width: Int, height: Int)], reaching side: Int, maximumPixels: Int) -> Int? {
        let allowed = sizes.indices
            .filter { sizes[$0].width > 0 && sizes[$0].height > 0 && sizes[$0].width * sizes[$0].height <= maximumPixels }
        func pixels(_ index: Int) -> Int {
            sizes[index].width * sizes[index].height
        }
        let reaching = allowed.filter { min(sizes[$0].width, sizes[$0].height) >= side }
        return reaching.min { pixels($0) < pixels($1) } ?? allowed.max { pixels($0) < pixels($1) }
    }

    private static func decode(_ source: CGImageSource, limits: Limits) -> CGImage? {
        guard let type = CGImageSourceGetType(source) as String?, limits.types.contains(type) else {
            return nil
        }
        let sizes = (0 ..< CGImageSourceGetCount(source)).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            return (
                width: properties?[kCGImagePropertyPixelWidth] as? Int ?? 0,
                height: properties?[kCGImagePropertyPixelHeight] as? Int ?? 0,
            )
        }
        guard let index = index(among: sizes, reaching: limits.maximumSide, maximumPixels: limits.maximumSourcePixels) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limits.maximumSide,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options), image.width > 0, image.height > 0 else {
            return nil
        }
        return image
    }
}
