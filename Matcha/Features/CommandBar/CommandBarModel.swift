import Foundation
import Observation
import OSLog

/// State of a window's command bar: opening and mode; the text, rows and selection are those of `results`, fed by the
/// open tabs, the actions, the history and the suggestions, in that order.
@MainActor
@Observable
final class CommandBarModel {
    private(set) var isPresented = false
    private(set) var mode = CommandBarMode.newTab
    /// Incremented on each open request: the field takes the keyboard back and selects all.
    private(set) var focusRequest = 0

    @ObservationIgnored let windowModel: WindowModel
    @ObservationIgnored let results: CommandBarResults

    /// No side effects: nothing starts before the first opening.
    init(
        windowModel: WindowModel,
        history: (any HistorySource)? = nil,
        suggestions: SearchSuggestionsProvider = SearchSuggestionsProvider(),
        ranker: CommandRanker = CommandRanker(),
        now: @escaping () -> Date = { .now },
    ) {
        self.windowModel = windowModel
        let actions = ActionsProvider(windowModel: windowModel)
        results = CommandBarResults(
            providers: [OpenTabsProvider(windowModel: windowModel), actions, HistoryProvider(source: history), suggestions],
            ranker: ranker,
            now: now,
            pristineActions: actions.available(in:),
        )
    }

    var text: String {
        results.text
    }

    var rows: [CommandRow] {
        results.rows
    }

    var selectedRowID: CommandRow.ID? {
        results.selectedRowID
    }

    var selectedRow: CommandRow? {
        results.selectedRow
    }

    /// Engine of the current opening (“Search …” subtitles).
    var searchEngine: SearchEngine {
        results.searchEngine
    }

    // MARK: Opening

    /// ⌘T and “New Tab”: the bar in new tab mode. With a home page for new tabs, the tab is created right away and
    /// the bar opens on its address.
    func newTab(_ settings: CommandBarSettings) {
        if let home = settings.newTabHomeURL {
            let tab = windowModel.tabManager.newTab(url: home)
            present(.currentTab(tab.id), text: home.absoluteString, pristineURL: home, settings: settings)
        } else {
            present(.newTab, text: "", pristineURL: nil, settings: settings)
        }
    }

    /// ⌘L and the address pill: editing of the displayed tab, or a new tab if there is none.
    func editCurrentTab(_ settings: CommandBarSettings) {
        if let tab = windowModel.selectedTab {
            present(.currentTab(tab.id), text: tab.url?.absoluteString ?? "", pristineURL: tab.url, settings: settings)
        } else {
            present(.newTab, text: "", pristineURL: nil, settings: settings)
        }
    }

    /// Settings changed while the bar is open (Settings window, bar left open): the engine and suggestions follow
    /// immediately.
    func apply(_ settings: CommandBarSettings) {
        guard isPresented else {
            return
        }
        results.apply(searchEngine: settings.searchEngine, context: makeContext(settings))
    }

    /// Already open in the same mode: the text stays, the field only takes the keyboard back.
    private func present(_ newMode: CommandBarMode, text: String, pristineURL: URL?, settings: CommandBarSettings) {
        focusRequest += 1
        if isPresented, newMode == mode {
            apply(settings)
            return
        }
        mode = newMode
        results.start(text: text, pristineURL: pristineURL, searchEngine: settings.searchEngine, context: makeContext(settings))
        isPresented = true
        Logger.commandBar.debug("Command bar opened")
    }

    private func makeContext(_ settings: CommandBarSettings) -> CommandContext {
        CommandContext(isPrivate: windowModel.session.isPrivate, showsSearchSuggestions: settings.showsSearchSuggestions)
    }

    // MARK: Input and selection

    /// New field text: rows rebuilt right away, first row selected, then sources queried in a task.
    func updateText(_ newText: String) {
        if isPresented {
            results.updateText(newText)
        }
    }

    func moveSelection(by delta: Int) {
        results.moveSelection(by: delta)
    }

    /// What follows Return (`rowID` nil: the selected row) or a click on a row.
    func submission(for rowID: CommandRow.ID?) -> CommandBarSubmission {
        guard isPresented else {
            return .ignore
        }
        if results.isBlank {
            return mode == .newTab ? .openEmptyTab : .ignore
        }
        return results.row(for: rowID).map { .run($0.target, mode: mode) } ?? .ignore
    }

    /// Closes the bar and forgets everything except `focusRequest`.
    func dismiss() {
        guard isPresented else {
            return
        }
        results.reset()
        isPresented = false
        mode = .newTab
        Logger.commandBar.debug("Command bar closed")
    }

    /// Tests: waits for the current search to finish.
    func waitForPendingResults() async {
        await results.waitForPendingResults()
    }
}
