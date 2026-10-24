import AppKit
import SwiftUI

/// Image of an avatar, made on this Mac (task 7.9): a photo cropped to a centered square and reduced, or an emoji or
/// initials drawn on a circle's background, small enough for the server (`maxAvatarBytes`).
enum AvatarImage {
    /// Side of an avatar's image, in pixels.
    static let side = 256

    /// JPEG of the photo at `url`; nil if it can't be read or made small enough.
    static func photo(from url: URL, maximumBytes: Int) -> Data? {
        guard let image = NSImage(contentsOf: url), let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let square = min(source.width, source.height)
        let crop = CGRect(x: (source.width - square) / 2, y: (source.height - square) / 2, width: square, height: square)
        guard let cropped = source.cropping(to: crop), let bitmap = render({ context, bounds in
            context.interpolationQuality = .high
            context.draw(cropped, in: bounds)
        }) else {
            return nil
        }
        for quality in [0.85, 0.7, 0.5, 0.35] {
            let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
            if let data, data.count <= maximumBytes {
                return data
            }
        }
        return nil
    }

    /// PNG of an emoji on a light background.
    static func emoji(_ emoji: String) -> Data? {
        draw(text: emoji, font: .systemFont(ofSize: CGFloat(side) * 0.62), color: .black, background: NSColor(white: 0.93, alpha: 1))
    }

    /// PNG of white initials on `color` (“#RRGGBB”).
    static func initials(_ initials: String, color: String) -> Data? {
        let font = NSFont.systemFont(ofSize: CGFloat(side) * 0.42, weight: .semibold)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: font.pointSize) } ?? font
        return draw(text: initials, font: rounded, color: .white, background: NSColor(self.color(color)))
    }

    /// The first two letters or digits typed, in uppercase.
    static func initials(from text: String) -> String {
        String(text.filter { $0.isLetter || $0.isNumber }.prefix(2)).uppercased()
    }

    /// Initials of an email: the first letter of the first two words of its name (“jeremy.mouton@…”: “JM”).
    static func initials(fromEmail email: String) -> String {
        let name = email.split(separator: "@").first ?? ""
        let words = name.split { !$0.isLetter && !$0.isNumber }
        return initials(from: words.prefix(2).compactMap(\.first).map(String.init).joined())
    }

    /// Color of “#RRGGBB”, in sRGB; the accent color otherwise.
    static func color(_ hex: String) -> Color {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else {
            return .accentColor
        }
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
        )
    }

    private static func draw(text: String, font: NSFont, color: NSColor, background: NSColor) -> Data? {
        let bitmap = render { context, bounds in
            context.setFillColor(background.cgColor)
            context.fill(bounds)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            let size = attributed.size()
            attributed.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        }
        return bitmap?.representation(using: .png, properties: [:])
    }

    /// Square bitmap of `side` pixels, drawn by `draw`.
    private static func render(_ draw: (CGContext, CGRect) -> Void) -> NSBitmapImageRep? {
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            return nil
        }
        let previous = NSGraphicsContext.current
        draw(context, CGRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.current = previous
        return context.makeImage().map(NSBitmapImageRep.init(cgImage:))
    }
}
