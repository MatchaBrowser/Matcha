import CoreGraphics
import Foundation
import ImageIO
@testable import Matcha
import Testing
import UniformTypeIdentifiers

/// Review TR3: images from outside decoded with bounds; the size a file announces is checked before decoding.
struct BoundedImageDecoderTests {
    /// PNG of `width` × `height` pixels, of one color.
    private func png(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func `of several sizes, the smallest that is sharp enough, never one too large`() {
        let sizes = [(width: 16, height: 16), (width: 32, height: 32), (width: 256, height: 256), (width: 512, height: 512)]
        #expect(BoundedImageDecoder.index(among: sizes, reaching: 128, maximumPixels: 1_000_000) == 2)
        // None reaches the side: the largest allowed.
        #expect(BoundedImageDecoder.index(among: Array(sizes.prefix(2)), reaching: 128, maximumPixels: 1_000_000) == 1)
        #expect(BoundedImageDecoder.index(
            among: [(width: 20000, height: 20000), (width: 48, height: 48)],
            reaching: 128,
            maximumPixels: 1_000_000,
        ) == 1)
        #expect(BoundedImageDecoder.index(among: [(width: 20000, height: 20000)], reaching: 128, maximumPixels: 1_000_000) == nil)
        #expect(BoundedImageDecoder.index(among: [], reaching: 128, maximumPixels: 1_000_000) == nil)
    }

    @Test func `a bitmap is decoded reduced, a vector image never`() throws {
        let image = try #require(try BoundedImageDecoder.decode(png(width: 600, height: 300), limits: .favicon))
        #expect(max(image.width, image.height) == BoundedImageDecoder.Limits.favicon.maximumSide)
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>"#.utf8)
        #expect(BoundedImageDecoder.decode(svg, limits: .favicon) == nil)
        #expect(BoundedImageDecoder.decode(svg, limits: .photo) == nil)
    }

    /// A one-color PNG of 2048 × 2048 pixels weighs a few kilobytes, and 16 MB once decoded: the size it announces
    /// is refused before decoding beyond the ceiling of icons, accepted within that of photos.
    @Test func `a small file announcing a large image is refused before decoding`() throws {
        let large = try png(width: 2048, height: 2048)
        #expect(large.count < 200_000)
        let source = try #require(CGImageSourceCreateWithData(large as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        #expect(properties?[kCGImagePropertyPixelWidth] as? Int == 2048)
        #expect(BoundedImageDecoder.decode(large, limits: .favicon) == nil)
        #expect(FaviconDecoder.decodeNow(large) == nil)
        #expect(BoundedImageDecoder.decode(large, limits: .photo) != nil)
    }

    @Test @MainActor func `a photo chosen for the avatar is reduced, then cropped to a square`() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "photo-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try png(width: 3000, height: 2000).write(to: url)
        let decoded = try #require(BoundedImageDecoder.decode(contentsOf: url, limits: .photo))
        #expect(max(decoded.width, decoded.height) == BoundedImageDecoder.Limits.photo.maximumSide)
        let avatar = try #require(AvatarImage.photo(from: url, maximumBytes: 270_000))
        let image = try #require(BoundedImageDecoder.decode(avatar, limits: .avatar))
        #expect(image.width == AvatarImage.side && image.height == AvatarImage.side)
    }

    @Test @MainActor func `the avatar received is decoded once, and refused if it isn't a bitmap`() throws {
        let sync = try SyncService(
            defaults: #require(UserDefaults(suiteName: "BoundedImageDecoderTests-\(UUID().uuidString)")),
            extensions: nil,
            directory: nil,
        )
        try sync.setAvatar(png(width: 256, height: 256))
        #expect(sync.avatarImage?.width == 256)
        sync.setAvatar(Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>"#.utf8))
        #expect(sync.avatar != nil && sync.avatarImage == nil)
        sync.setAvatar(nil)
        #expect(sync.avatarImage == nil)
    }
}
