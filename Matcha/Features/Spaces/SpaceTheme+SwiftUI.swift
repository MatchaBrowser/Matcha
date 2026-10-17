import AppKit
import SwiftUI

nonisolated extension SpaceTheme {
    /// Couleurs de la variante adaptée à l'apparence.
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

    /// Couleur choisie dans un sélecteur, convertie en sRGB.
    init(_ color: Color) {
        let srgb = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
    }
}
