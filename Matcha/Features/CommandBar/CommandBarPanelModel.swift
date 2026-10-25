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
