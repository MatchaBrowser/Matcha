import Foundation

/// Allure d'une icône de site, pour la rendre lisible sur un fond clair comme sombre.
nonisolated enum FaviconTone: Equatable, Sendable {
    /// Dessin sombre et sans couleur sur fond transparent (GitHub, X, Notion…) : invisible sur fond sombre.
    case dark
    /// Dessin clair et sans couleur sur fond transparent : invisible sur fond clair.
    case light
    /// Icône colorée ou qui porte son propre fond : lisible partout.
    case neutral

    /// Analyse des pixels RGBA (8 bits, alpha prémultiplié, comme `NSBitmapImageRep`).
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
            // Retire la prémultiplication pour retrouver la vraie couleur.
            let red = Double(pixels[index * 4]) / alpha
            let green = Double(pixels[index * 4 + 1]) / alpha
            let blue = Double(pixels[index * 4 + 2]) / alpha
            luminance += 0.2126 * red + 0.7152 * green + 0.0722 * blue
            saturation += max(red, green, blue) - min(red, green, blue)
            opaque += 1
        }
        // Une icône sans transparence porte son propre fond.
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
