import Foundation

/// Contraste selon les WCAG 2 : luminance relative et rapport de contraste, pour choisir un texte lisible sur un fond.
nonisolated extension ThemeColor {
    /// Luminance relative (0 : noir, 1 : blanc) : composantes sRGB linéarisées, pondérées selon la sensibilité de l'œil.
    var relativeLuminance: Double {
        0.2126 * Self.linearized(red) + 0.7152 * Self.linearized(green) + 0.0722 * Self.linearized(blue)
    }

    /// Rapport de contraste avec `other`, de 1 (aucun) à 21 (noir sur blanc), quel que soit l'ordre.
    func contrastRatio(with other: ThemeColor) -> Double {
        let (lighter, darker) = (max(relativeLuminance, other.relativeLuminance), min(relativeLuminance, other.relativeLuminance))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Texte à écrire sur cette couleur prise comme fond : le noir ou le blanc, celui qui contraste le plus
    /// (le blanc à égalité).
    var readableTextColor: ThemeColor {
        contrastRatio(with: .black) > contrastRatio(with: .white) ? .black : .white
    }

    /// Composante sRGB ramenée à une intensité lumineuse linéaire (courbe de transfert sRGB).
    private static func linearized(_ component: Double) -> Double {
        component <= 0.040_45 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
}
