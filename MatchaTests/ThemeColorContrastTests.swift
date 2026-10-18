import Foundation
@testable import Matcha
import Testing

/// Contraste WCAG 2 : luminance relative, rapport de contraste, texte lisible sur un fond.
struct ThemeColorContrastTests {
    @Test func `relative luminance follows the sRGB curve`() {
        #expect(ThemeColor.black.relativeLuminance == 0)
        #expect(abs(ThemeColor.white.relativeLuminance - 1) < 1e-12)
        // Gris moyen : 0,5 en sRGB n'est que 21 % de la lumière du blanc.
        #expect(abs(ThemeColor(red: 0.5, green: 0.5, blue: 0.5).relativeLuminance - 0.214_04) < 1e-4)
        // Partie linéaire de la courbe, près du noir.
        #expect(abs(ThemeColor(red: 0.03, green: 0.03, blue: 0.03).relativeLuminance - 0.03 / 12.92) < 1e-12)
        // Le vert pèse le plus.
        #expect(ThemeColor(red: 0, green: 1, blue: 0).relativeLuminance > ThemeColor(red: 1, green: 0, blue: 0).relativeLuminance)
    }

    @Test func `contrast ratio goes from 1 to 21 in any order`() {
        #expect(abs(ThemeColor.white.contrastRatio(with: .black) - 21) < 1e-9)
        #expect(ThemeColor.black.contrastRatio(with: .white) == ThemeColor.white.contrastRatio(with: .black))
        #expect(ThemeColor(rgb: 0x007AFF).contrastRatio(with: ThemeColor(rgb: 0x007AFF)) == 1)
        // #767676 sur blanc : 4,54, le gris le plus clair qui passe le niveau AA.
        #expect(abs(ThemeColor(rgb: 0x767676).contrastRatio(with: .white) - 4.54) < 0.01)
    }

    @Test func `readable text is black on light backgrounds and white on dark ones`() {
        #expect(ThemeColor.white.readableTextColor == .black)
        #expect(ThemeColor.black.readableTextColor == .white)
        #expect(ThemeColor(rgb: 0xFFCC00).readableTextColor == .black)
        #expect(ThemeColor(rgb: 0x5856D6).readableTextColor == .white)
        #expect(ThemeColor(rgb: 0x1C1C1E).readableTextColor == .white)
    }

    /// Le meilleur du noir et du blanc dépasse toujours 4,5:1 (niveau AA des WCAG) : au pire, pour une luminance de
    /// 0,179, les deux donnent 4,58.
    @Test func `the readable color always reaches the AA level`() {
        var backgrounds = FolderColorPreset.all.map(\.color)
        for level in stride(from: 0, through: 255, by: 5) {
            let value = Double(level) / 255
            backgrounds.append(ThemeColor(red: value, green: value, blue: value))
            backgrounds.append(ThemeColor(red: value, green: 1 - value, blue: 0.5))
        }
        for background in backgrounds {
            #expect(background.contrastRatio(with: background.readableTextColor) >= 4.5, "\(background.hexString)")
        }
    }
}
