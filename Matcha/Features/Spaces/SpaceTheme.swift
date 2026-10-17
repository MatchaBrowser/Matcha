import Foundation

/// Thème d'un Space : 2 ou 3 couleurs de base et l'angle du dégradé. Les variantes claire et sombre en
/// sont tirées, pour que le texte de la barre reste lisible dans les deux apparences.
nonisolated struct SpaceTheme: Codable, Hashable, Sendable {
    static let colorCountRange = 2 ... 3

    /// Nom du thème prédéfini d'origine, nil pour un thème personnalisé.
    var name: String?
    private(set) var colors: [ThemeColor]
    /// Direction du dégradé en degrés, comme en CSS : 0 vers le haut, 90 vers la droite, 180 vers le bas.
    var angle: Double

    init(name: String? = nil, colors: [ThemeColor], angle: Double = 135) {
        self.name = name
        self.colors = Self.fitted(colors)
        self.angle = angle
    }

    /// Remplace les couleurs ; il en faut 2 ou 3 (la dernière est répétée ou les dernières retirées).
    mutating func setColors(_ newColors: [ThemeColor]) {
        colors = Self.fitted(newColors)
        name = nil
    }

    /// Variante claire : couleurs éclaircies vers un pastel.
    var lightColors: [ThemeColor] {
        colors.map { $0.mixed(with: .white, amount: 0.65) }
    }

    /// Variante sombre : couleurs assombries.
    var darkColors: [ThemeColor] {
        colors.map { $0.mixed(with: .black, amount: 0.7) }
    }

    /// Direction du dégradé ramenée au carré unité (vers la droite et vers le bas), la plus grande
    /// composante valant 1 en valeur absolue, pour que le dégradé aille d'un bord (ou d'un coin) à l'autre.
    var direction: (horizontal: Double, vertical: Double) {
        let radians = angle * .pi / 180
        let (horizontal, vertical) = (sin(radians), -cos(radians))
        let scale = max(abs(horizontal), abs(vertical))
        return (horizontal / scale, vertical / scale)
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Thème lu dans `data`, ou nil si `data` est vide ou illisible.
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
