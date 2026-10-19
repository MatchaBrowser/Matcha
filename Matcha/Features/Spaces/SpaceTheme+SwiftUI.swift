import AppKit
import SwiftUI

nonisolated extension SpaceTheme {
    /// Colors of the variant suited to the appearance.
    func swiftUIColors(for colorScheme: ColorScheme) -> [Color] {
        (colorScheme == .dark ? darkColors : lightColors).map(\.color)
    }

    var startPoint: UnitPoint {
        let (horizontal, vertical) = direction
        return UnitPoint(x: 0.5 - horizontal / 2, y: 0.5 - vertical / 2)
    }

    var endPoint: UnitPoint {
        let (horizontal, vertical) = direction
        return UnitPoint(x: 0.5 + horizontal / 2, y: 0.5 + vertical / 2)
    }
}

extension ThemeColor {
    nonisolated var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }

    /// Color chosen in a picker, converted to sRGB.
    init(_ color: Color) {
        let srgb = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
    }
}
