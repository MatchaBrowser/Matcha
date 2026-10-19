import Foundation

/// Storable sRGB color, components between 0 and 1.
nonisolated struct ThemeColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    /// Mix with `other`: 0 gives this color, 1 gives `other`.
    func mixed(with other: ThemeColor, amount: Double) -> ThemeColor {
        let amount = Self.clamp(amount)
        return ThemeColor(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount,
        )
    }

    static let white = ThemeColor(red: 1, green: 1, blue: 1)
    static let black = ThemeColor(red: 0, green: 0, blue: 0)

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
