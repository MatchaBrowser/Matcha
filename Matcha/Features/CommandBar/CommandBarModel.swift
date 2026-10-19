import Foundation
import Observation
import OSLog

/// State of a window's command bar: opening, mode, text, rows and selection.
///
/// Each keystroke rebuilds the rows right away (rows from the text, then results already received, re-ranked),
/// then a single task queries the sources in order: tabs, actions, history, suggestions. The rows are republished
/// after each source; a more recent keystroke cancels the current task.
@MainActor
@Observable
final class CommandBarModel {
    private(set) var isPresented = false
    private(set) var mode = CommandBarMode.newTab
    private(set) var text = ""
    private(set) var rows: [CommandRow] = []
    private(set) var selectedRowID: CommandRow.ID?
    /// Incremented on each open request: the field takes the keyboard back and selects all.
    private(set) var focusRequest = 0
    /// Engine of the current opening (“Search …” subtitles).
    private(set) var searchEngine = SearchEngine.defaultEngine

    @ObservationIgnored let windowModel: WindowModel
    @ObservationIgnored private let actions: ActionsProvider
    /// Tabs, actions, history, suggestions (always last).
    @ObservationIgnored private let providers: [any CommandProvider]
    @ObservationIgnored private let ranker: CommandRanker
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var context = CommandContext()
    /// Results received, one array per source.
    @ObservationIgnored private var candidates: [[CommandCandidate]]
    /// ⌘L address as long as the text has not been modified.
    @ObservationIgnored private var pristineURL: URL?
    @ObservationIgnored private var queryTask: Task<Void, Never>?

    /// No side effects: nothing starts before the first opening.
    init(
        windowModel: WindowModel,
        history: (any HistorySource)? = nil,
        suggestions: SearchSuggestionsProvider = SearchSuggestionsProvider(),
        ranker: CommandRanker = CommandRanker(),
        now: @escaping () -> Date = { .now },
    ) {
        self.windowModel = windowModel
        actions = ActionsProvider(windowModel: windowModel)
        providers = [OpenTabsProvider(windowModel: windowModel), actions, HistoryProvider(source: history), suggestions]
        self.ranker = ranker
        self.now = now
        candidates = Array(repeating: [], count: providers.count)
    }

    var selectedRow: CommandRow? {
        rows.first { $0.id == selectedRowID }
    }

    // MARK: Opening

    /// ⌘T and “New Tab”: the bar in new tab mode. With a home page for new tabs, the tab is created right away and
    /// the bar opens on its address.
    func newTab(_ settings: CommandBarSettings) {
        if let home = settings.newTabHomeURL {
            let tab = windowModel.space.tabManager.newTab(url: home)
            present(.currentTab(tab.id), text: home.absoluteString, pristineURL: home, settings: settings)
        } else {
            present(.newTab, text: "", pristineURL: nil, settings: settings)
        }
    }

    /// ⌘L and the address pill: editing of the displayed tab, or a new tab if there is none.
    func editCurrentTab(_ settings: CommandBarSettings) {
        if let tab = windowModel.space.tabManager.selectedTab {
            present(.currentTab(tab.id), text: tab.url?.absoluteString ?? "", pristineURL: tab.url, settings: settings)
        } else {
            present(.newTab, text: "", pristineURL: nil, settings: settings)
        }
    }

    /// Settings changed while the bar is open (Settings window, bar left open): the engine and suggestions follow
    /// immediately. Suggestions already received are forgotten and the sources queried again.
    func apply(_ settings: CommandBarSettings) {
        let newContext = makeContext(settings)
        guard isPresented, settings.searchEngine != searchEngine || newContext != context else {
            return
        }
        searchEngine = settings.searchEngine
        context = newContext
        cancelQuery()
        if let last = candidates.indices.last {
            candidates[last] = []
        }
        refresh(resetSelection: false)
        startQuery(CommandQuery(text: text, searchEngine: searchEngine))
    }

    /// Already open in the same mode: the text stays, the field only takes the keyboard back.
    private func present(_ newMode: CommandBarMode, text newText: String, pristineURL newPristineURL: URL?, settings: CommandBarSettings) {
        focusRequest += 1
        if isPresented, newMode == mode {
            apply(settings)
            return
        }
        cancelQuery()
        mode = newMode
        text = newText
        pristineURL = newPristineURL
        searchEngine = settings.searchEngine
        context = makeContext(settings)
        candidates = Array(repeating: [], count: providers.count)
        isPresented = true
        refresh(resetSelection: true)
        Logger.commandBar.debug("Command bar opened")
    }

    // MARK: Input and selection

    /// New field text: rows rebuilt right away, first row selected, then sources queried in a task.
    func updateText(_ newText: String) {
        guard isPresented, newText != text else {
            return
        }
        text = newText
        // The first modification ends the ⌘L address for good.
        pristineURL = nil
        cancelQuery()
        let query = CommandQuery(text: newText, searchEngine: searchEngine)
        if let last = candidates.indices.last {
            candidates[last] = CommandRanker.carriedOver(candidates[last], to: query)
        }
        refresh(resetSelection: true)
        startQuery(query)
    }

    /// Moves the selection, bounded by the rows, without wrapping.
    func moveSelection(by delta: Int) {
        guard !rows.isEmpty else {
            return
        }
        let current = rows.firstIndex { $0.id == selectedRowID } ?? 0
        selectedRowID = rows[min(max(current + delta, 0), rows.count - 1)].id
    }

    /// What follows Return (`rowID` nil: the selected row) or a click on a row.
    func submission(for rowID: CommandRow.ID?) -> CommandBarSubmission {
        guard isPresented else {
            return .ignore
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, pristineURL == nil {
            return mode == .newTab ? .openEmptyTab : .ignore
        }
        let id = rowID ?? selectedRowID
        guard let row = rows.first(where: { $0.id == id }) ?? rows.first else {
            return .ignore
        }
        return .run(row.target, mode: mode)
    }

    /// Closes the bar and forgets everything except `focusRequest`.
    func dismiss() {
        guard isPresented else {
            return
        }
        cancelQuery()
        isPresented = false
        text = ""
        rows = []
        selectedRowID = nil
        pristineURL = nil
        candidates = Array(repeating: [], count: providers.count)
        mode = .newTab
        Logger.commandBar.debug("Command bar closed")
    }

    /// Tests: waits for the current search to finish.
    func waitForPendingResults() async {
        await queryTask?.value
    }

    // MARK: Results

    private func makeContext(_ settings: CommandBarSettings) -> CommandContext {
        CommandContext(isPrivate: windowModel.session.isPrivate, showsSearchSuggestions: settings.showsSearchSuggestions)
    }

    /// Queries the sources in a task, except for an empty text or the unmodified ⌘L address.
    private func startQuery(_ query: CommandQuery) {
        guard pristineURL == nil, !query.isEmpty else {
            return
        }
        let context = context
        queryTask = Task { [weak self] in
            await self?.gather(query, context: context)
        }
    }

    private func gather(_ query: CommandQuery, context: CommandContext) async {
        for index in providers.indices {
            let found = await providers[index].candidates(for: query, context: context)
            guard !Task.isCancelled else {
                return
            }
            candidates[index] = found
            refresh(resetSelection: false)
        }
    }

    /// Recomputes the rows; the selection returns to the first row if requested or if the selected row has
    /// disappeared.
    private func refresh(resetSelection: Bool) {
        let query = CommandQuery(text: text, searchEngine: searchEngine)
        let newRows = if let pristineURL {
            ranker.pristineRows(currentURL: pristineURL, actions: actions.available(in: context))
        } else if query.isEmpty {
            [CommandRow]()
        } else {
            ranker.rank(query, candidates: candidates.flatMap(\.self), now: now())
        }
        if newRows != rows {
            rows = newRows
        }
        let keepsSelection = !resetSelection && rows.contains { $0.id == selectedRowID }
        let newSelection = keepsSelection ? selectedRowID : rows.first?.id
        if newSelection != selectedRowID {
            selectedRowID = newSelection
        }
    }

    private func cancelQuery() {
        queryTask?.cancel()
        queryTask = nil
    }
}
