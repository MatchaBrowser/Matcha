import Foundation

/// Look of a website icon, to make it legible on a light background as well as a dark one.
nonisolated enum FaviconTone: Equatable, Sendable {
    /// Dark, colorless drawing on a transparent background (GitHub, X, Notion…): invisible on a dark background.
    case dark
    /// Light, colorless drawing on a transparent background: invisible on a light background.
    case light
    /// Colored icon or one with its own background: legible everywhere.
    case neutral

    /// Analysis of RGBA pixels (8 bits, premultiplied alpha, like `NSBitmapImageRep`).
    static func analyze(rgba pixels: [UInt8]) -> FaviconTone {
        var transparent = 0
        var opaque = 0
        var luminance = 0.0
        var saturation = 0.0
        let count = pixels.count / 4
        for index in 0 ..< count {
            let alpha = Double(pixels[index * 4 + 3])
            if alpha < 32 {
                transparent += 1
                continue
            }
            guard alpha >= 128 else {
                continue
            }
            // Removes the premultiplication to get back the true color.
            let red = Double(pixels[index * 4]) / alpha
            let green = Double(pixels[index * 4 + 1]) / alpha
            let blue = Double(pixels[index * 4 + 2]) / alpha
            luminance += 0.2126 * red + 0.7152 * green + 0.0722 * blue
            saturation += max(red, green, blue) - min(red, green, blue)
            opaque += 1
        }
        // An icon without transparency carries its own background.
        guard opaque > 0, count > 0, Double(transparent) / Double(count) >= 0.15 else {
            return .neutral
        }
        let meanLuminance = luminance / Double(opaque)
        let meanSaturation = saturation / Double(opaque)
        guard meanSaturation < 0.25 else {
            return .neutral
        }
        if meanLuminance < 0.3 {
            return .dark
        }
        if meanLuminance > 0.8 {
            return .light
        }
        return .neutral
    }
}
