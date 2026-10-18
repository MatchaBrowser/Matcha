import Foundation

/// Couleur écrite en hexadécimal « #RRGGBB » (sRGB, 8 bits par composante) : forme enregistrée des couleurs d'un dossier.
nonisolated extension ThemeColor {
    /// Couleur `0xRRGGBB`.
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
        )
    }

    /// Couleur lue dans « #RRGGBB » ou « RRGGBB » (majuscules ou minuscules) ; nil pour tout autre texte.
    init?(hexString: String) {
        let digits = hexString.hasPrefix("#") ? hexString.dropFirst() : Substring(hexString)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let rgb = UInt32(digits, radix: 16) else {
            return nil
        }
        self.init(rgb: rgb)
    }

    /// « #RRGGBB », en majuscules, chaque composante arrondie au plus proche des 256 niveaux.
    var hexString: String {
        let levels = [red, green, blue].map { Int(($0 * 255).rounded()) }
        return "#" + levels.map { String(format: "%02X", $0) }.joined()
    }
}
