import Foundation

/// Page zoom levels (task 5.4), Safari's: from 50% to 300%. ⌘+ and ⌘- move to the next or previous level from any
/// zoom (a zoom outside the list joins the nearest level in the requested direction); ⌘0 goes back to 100%.
nonisolated enum ZoomLevels {
    static let steps: [Double] = [0.5, 0.75, 0.85, 1, 1.15, 1.25, 1.5, 1.75, 2, 2.5, 3]
    static let actualSize = 1.0
    /// Difference below which two zooms are equal (`pageZoom` is a `CGFloat` that may have been rounded).
    static let tolerance = 0.001

    static var minimum: Double {
        steps[0]
    }

    static var maximum: Double {
        steps[steps.count - 1]
    }

    /// What a zoom command asks for.
    enum Change: Sendable {
        case zoomIn, zoomOut, actualSize

        /// Zoom after the command, from `current`; nil if it changes nothing (end of the list, already at 100%).
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

    /// First level above `current`; nil at the maximum or beyond.
    static func step(after current: Double) -> Double? {
        steps.first { $0 > current + tolerance }
    }

    /// Last level below `current`; nil at the minimum or below.
    static func step(before current: Double) -> Double? {
        steps.last { $0 < current - tolerance }
    }

    static func isActualSize(_ level: Double) -> Bool {
        abs(level - actualSize) <= tolerance
    }

    /// `level` clamped between the minimum and the maximum; 100% if it is not a finite number.
    static func clamped(_ level: Double) -> Double {
        level.isFinite ? min(max(level, minimum), maximum) : actualSize
    }

    /// Displayed zoom: “125 %” (depending on the language: “125%” in English).
    static func percentText(_ level: Double, locale: Locale = .autoupdatingCurrent) -> String {
        level.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }
}
