import Foundation

/// What the command bar panel reads and modifies: the bar of a browser window (`CommandBarModel`) or that of a
/// mini window (`MiniCommandBarModel`).
@MainActor
protocol CommandBarPanelModel: AnyObject {
    var isPresented: Bool { get }
    var text: String { get }
    var rows: [CommandRow] { get }
    var selectedRowID: CommandRow.ID? { get }
    var selectedRow: CommandRow? { get }
    /// Changes on each open request: the field takes the keyboard back and selects all.
    var focusRequest: Int { get }
    /// Engine of the current opening (“Search …”).
    var searchEngine: SearchEngine { get }
    /// Tab whose address is being modified (field icon); nil for a fresh entry.
    var editedTab: BrowserTab? { get }
    /// Row icons.
    var rowIcons: CommandRowIcons { get }
    func updateText(_ newText: String)
    func moveSelection(by delta: Int)
    func dismiss()
}

/// What a row needs for its icon.
@MainActor
struct CommandRowIcons {
    let faviconService: FaviconService
    /// Live tab of a tab row; nil if it no longer exists (or if the bar does not offer tabs).
    let tab: (TabReference) -> BrowserTab?
}

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
