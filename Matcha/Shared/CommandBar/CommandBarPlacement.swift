import Foundation

/// Place of the panel in its window.
nonisolated enum CommandBarPlacement: Equatable, Sendable {
    /// Browser window: centered, 640 pt at most, top at 18% of the height (52 pt at least).
    case window
    /// Mini window: full width minus 10 pt on each side, `top` pt below the top of the window.
    case belowToolbar(top: Double)

    func top(inHeight height: Double) -> Double {
        switch self {
        case .window: max(52, (height * 0.18).rounded())
        case let .belowToolbar(top): top
        }
    }

    var maximumWidth: Double {
        self == .window ? 640 : .infinity
    }

    var horizontalMargin: Double {
        self == .window ? 24 : 10
    }

    var bottomMargin: Double {
        self == .window ? 24 : 10
    }
}
