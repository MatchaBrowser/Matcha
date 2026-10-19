import Foundation

/// Contrast according to WCAG 2: relative luminance and contrast ratio, to choose readable text on a background.
nonisolated extension ThemeColor {
    /// Relative luminance (0: black, 1: white): linearized sRGB components, weighted by the eye's sensitivity.
    var relativeLuminance: Double {
        0.2126 * Self.linearized(red) + 0.7152 * Self.linearized(green) + 0.0722 * Self.linearized(blue)
    }

    /// Contrast ratio with `other`, from 1 (none) to 21 (black on white), whatever the order.
    func contrastRatio(with other: ThemeColor) -> Double {
        let (lighter, darker) = (max(relativeLuminance, other.relativeLuminance), min(relativeLuminance, other.relativeLuminance))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Text to write on this color used as a background: black or white, whichever contrasts most
    /// (white on a tie).
    var readableTextColor: ThemeColor {
        contrastRatio(with: .black) > contrastRatio(with: .white) ? .black : .white
    }

    /// sRGB component converted to a linear light intensity (sRGB transfer curve).
    private static func linearized(_ component: Double) -> Double {
        component <= 0.040_45 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
}
