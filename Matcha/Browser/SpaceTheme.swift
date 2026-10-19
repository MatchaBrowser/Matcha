import Foundation

/// Theme of a Space: 2 or 3 base colors and the gradient's angle. The light and dark variants are
/// derived from them, so that the sidebar's text stays readable in both appearances.
nonisolated struct SpaceTheme: Codable, Hashable, Sendable {
    static let colorCountRange = 2 ... 3

    /// Name of the original predefined theme, nil for a custom theme.
    var name: String?
    private(set) var colors: [ThemeColor]
    /// Direction of the gradient in degrees, as in CSS: 0 upwards, 90 to the right, 180 downwards.
    var angle: Double

    init(name: String? = nil, colors: [ThemeColor], angle: Double = 135) {
        self.name = name
        self.colors = Self.fitted(colors)
        self.angle = angle
    }

    /// Replaces the colors; there must be 2 or 3 (the last one is repeated or the last ones removed).
    mutating func setColors(_ newColors: [ThemeColor]) {
        colors = Self.fitted(newColors)
        name = nil
    }

    /// Light variant: colors lightened towards a pastel.
    var lightColors: [ThemeColor] {
        colors.map { $0.mixed(with: .white, amount: 0.65) }
    }

    /// Dark variant: darkened colors.
    var darkColors: [ThemeColor] {
        colors.map { $0.mixed(with: .black, amount: 0.7) }
    }

    /// Direction of the gradient brought back to the unit square (to the right and downwards), the largest
    /// component being 1 in absolute value, so that the gradient goes from one edge (or corner) to the other.
    var direction: (horizontal: Double, vertical: Double) {
        let radians = angle * .pi / 180
        let (horizontal, vertical) = (sin(radians), -cos(radians))
        let scale = max(abs(horizontal), abs(vertical))
        return (horizontal / scale, vertical / scale)
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Theme read from `data`, or nil if `data` is empty or unreadable.
    static func decoded(from data: Data?) -> SpaceTheme? {
        data.flatMap { try? JSONDecoder().decode(SpaceTheme.self, from: $0) }
    }

    private static func fitted(_ colors: [ThemeColor]) -> [ThemeColor] {
        var fitted = Array(colors.prefix(colorCountRange.upperBound))
        while fitted.count < colorCountRange.lowerBound {
            fitted.append(fitted.last ?? ThemeColor(red: 0.5, green: 0.5, blue: 0.5))
        }
        return fitted
    }
}
