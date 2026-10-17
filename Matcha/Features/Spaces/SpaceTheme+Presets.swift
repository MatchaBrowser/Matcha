import Foundation

/// Thèmes prédéfinis proposés par l'éditeur.
nonisolated extension SpaceTheme {
    static let lavender = SpaceTheme(name: "Lavande", colors: [
        ThemeColor(red: 0.42, green: 0.48, blue: 0.85), ThemeColor(red: 0.66, green: 0.48, blue: 0.82),
    ])
    static let ocean = SpaceTheme(name: "Océan", colors: [
        ThemeColor(red: 0.16, green: 0.50, blue: 0.80), ThemeColor(red: 0.15, green: 0.70, blue: 0.72),
    ])
    static let forest = SpaceTheme(name: "Forêt", colors: [
        ThemeColor(red: 0.22, green: 0.58, blue: 0.40), ThemeColor(red: 0.55, green: 0.70, blue: 0.30),
    ])
    static let sunset = SpaceTheme(name: "Couchant", colors: [
        ThemeColor(red: 0.95, green: 0.50, blue: 0.30), ThemeColor(red: 0.90, green: 0.35, blue: 0.55),
        ThemeColor(red: 0.62, green: 0.38, blue: 0.80),
    ])
    static let rose = SpaceTheme(name: "Rose", colors: [
        ThemeColor(red: 0.92, green: 0.45, blue: 0.62), ThemeColor(red: 0.96, green: 0.68, blue: 0.62),
    ])
    static let graphite = SpaceTheme(name: "Graphite", colors: [
        ThemeColor(red: 0.45, green: 0.47, blue: 0.52), ThemeColor(red: 0.30, green: 0.32, blue: 0.36),
    ])

    static let presets = [lavender, ocean, forest, sunset, rose, graphite]
    static let `default` = lavender

    /// Nom affiché d'un thème prédéfini, dans la langue de l'utilisateur. `name` reste l'identifiant
    /// enregistré avec le thème (en français) : il n'est jamais traduit. Nil pour un thème personnalisé.
    var displayName: LocalizedStringResource? {
        switch name {
        case Self.lavender.name: LocalizedStringResource("Lavender", comment: "Space theme preset")
        case Self.ocean.name: LocalizedStringResource("Ocean", comment: "Space theme preset")
        case Self.forest.name: LocalizedStringResource("Forest", comment: "Space theme preset")
        case Self.sunset.name: LocalizedStringResource("Sunset", comment: "Space theme preset")
        case Self.rose.name: LocalizedStringResource("Rose", comment: "Space theme preset (a pink color)")
        case Self.graphite.name: LocalizedStringResource("Graphite", comment: "Space theme preset (a dark gray color)")
        default: nil
        }
    }

    /// Thème fixe des fenêtres privées (toujours en apparence sombre).
    static let privateBrowsing = SpaceTheme(name: "Privé", colors: [
        ThemeColor(red: 0.30, green: 0.30, blue: 0.36), ThemeColor(red: 0.16, green: 0.16, blue: 0.20),
    ])
}
