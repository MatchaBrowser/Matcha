import Foundation

/// Color written in hexadecimal “#RRGGBB” (sRGB, 8 bits per component): the saved form of a folder's colors.
nonisolated extension ThemeColor {
    /// Color `0xRRGGBB`.
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
        )
    }

    /// Color read from “#RRGGBB” or “RRGGBB” (uppercase or lowercase); nil for any other text.
    init?(hexString: String) {
        let digits = hexString.hasPrefix("#") ? hexString.dropFirst() : Substring(hexString)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let rgb = UInt32(digits, radix: 16) else {
            return nil
        }
        self.init(rgb: rgb)
    }

    /// “#RRGGBB”, in uppercase, each component rounded to the nearest of the 256 levels.
    var hexString: String {
        let levels = [red, green, blue].map { Int(($0 * 255).rounded()) }
        return "#" + levels.map { String(format: "%02X", $0) }.joined()
    }
}
