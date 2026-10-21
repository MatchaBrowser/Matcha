import AppKit

/// What a double click on a title bar does, as chosen in System Settings > Desktop & Dock (“Double-click a window's
/// title bar to”). AppKit has no API for it: the choice is read from the global preferences, like other browsers do.
nonisolated enum TitleBarDoubleClick: Equatable {
    case zoom
    case minimize
    case nothing

    /// Global preference holding the choice: “Maximize” (zoom), “Fill”, “Minimize” or “None”.
    static let actionKey = "AppleActionOnDoubleClick"
    /// Its predecessor, still read when the choice was never made: minimize instead of zoom.
    static let minimizesKey = "AppleMiniaturizeOnDoubleClick"

    /// Zoom when nothing is set, as macOS does; “Fill” (window tiling) zooms too.
    init(action: String?, minimizes: Bool) {
        switch action {
        case "Minimize": self = .minimize
        case "None": self = .nothing
        case .some: self = .zoom
        case nil: self = minimizes ? .minimize : .zoom
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> Self {
        Self(action: defaults.string(forKey: actionKey), minimizes: defaults.bool(forKey: minimizesKey))
    }

    @MainActor
    func perform(on window: NSWindow) {
        switch self {
        case .zoom: window.zoom(nil)
        case .minimize: window.miniaturize(nil)
        case .nothing: break
        }
    }
}
