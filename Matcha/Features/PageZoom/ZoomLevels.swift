import Foundation

/// Niveaux de zoom des pages (tâche 5.4), ceux de Safari : de 50 % à 300 %. ⌘+ et ⌘- passent au niveau suivant ou
/// précédent depuis n'importe quel zoom (un zoom hors de la liste rejoint le niveau le plus proche dans le sens
/// demandé) ; ⌘0 revient à 100 %.
nonisolated enum ZoomLevels {
    static let steps: [Double] = [0.5, 0.75, 0.85, 1, 1.15, 1.25, 1.5, 1.75, 2, 2.5, 3]
    static let actualSize = 1.0
    /// Écart en dessous duquel deux zooms sont égaux (`pageZoom` est un `CGFloat` qui peut avoir été arrondi).
    static let tolerance = 0.001

    static var minimum: Double {
        steps[0]
    }

    static var maximum: Double {
        steps[steps.count - 1]
    }

    /// Ce que demande une commande de zoom.
    enum Change: Sendable {
        case zoomIn, zoomOut, actualSize

        /// Zoom après la commande, depuis `current` ; nil si elle ne change rien (bout de la liste, déjà à 100 %).
        func level(from current: Double) -> Double? {
            switch self {
            case .zoomIn:
                ZoomLevels.step(after: current)
            case .zoomOut:
                ZoomLevels.step(before: current)
            case .actualSize:
                ZoomLevels.isActualSize(current) ? nil : ZoomLevels.actualSize
            }
        }
    }

    /// Premier niveau au-dessus de `current` ; nil au maximum ou au-delà.
    static func step(after current: Double) -> Double? {
        steps.first { $0 > current + tolerance }
    }

    /// Dernier niveau au-dessous de `current` ; nil au minimum ou en deçà.
    static func step(before current: Double) -> Double? {
        steps.last { $0 < current - tolerance }
    }

    static func isActualSize(_ level: Double) -> Bool {
        abs(level - actualSize) <= tolerance
    }

    /// `level` ramené entre le minimum et le maximum ; 100 % s'il n'est pas un nombre fini.
    static func clamped(_ level: Double) -> Double {
        level.isFinite ? min(max(level, minimum), maximum) : actualSize
    }

    /// Zoom affiché : « 125 % » (selon la langue : « 125% » en anglais).
    static func percentText(_ level: Double, locale: Locale = .autoupdatingCurrent) -> String {
        level.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }
}
