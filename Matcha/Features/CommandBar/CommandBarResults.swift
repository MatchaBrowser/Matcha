import Foundation
import Observation

/// Text, rows and selection of a command bar, shared by the bar of a browser window and that of a mini window, which
/// differ by their sources and actions (audit C6).
///
/// Each keystroke rebuilds the rows right away (rows from the text, then results already received, re-ranked), then a
/// single task queries the sources: those that answer at once, ranked together, then the history and the suggestions
/// at the same time (review IU2); the rows are republished after each of these, and a more recent keystroke cancels
/// the current task. The unmodified ⌘L address shows its own rows and queries nothing.
@MainActor
@Observable
final class CommandBarResults {
    private(set) var text = ""
    private(set) var rows: [CommandRow] = []
    private(set) var selectedRowID: CommandRow.ID?
    /// Engine of the current opening (“Search …” subtitles).
    private(set) var searchEngine = SearchEngine.defaultEngine

    @ObservationIgnored private(set) var context = CommandContext()
    /// ⌘L address as long as the text has not been modified.
    @ObservationIgnored private(set) var pristineURL: URL?
    /// Sources, queried in this order; the last one (suggestions) is the one carried over from one keystroke to the next.
    @ObservationIgnored private let providers: [any CommandProvider]
    @ObservationIgnored private let ranker: CommandRanker
    @ObservationIgnored private let now: () -> Date
    /// Actions offered under an unmodified ⌘L address.
    @ObservationIgnored private let pristineActions: (CommandContext) -> [CommandCandidate]
    /// Results received, one array per source.
    @ObservationIgnored private var candidates: [[CommandCandidate]]
    @ObservationIgnored private var queryTask: Task<Void, Never>?

    init(
        providers: [any CommandProvider],
        ranker: CommandRanker,
        now: @escaping () -> Date,
        pristineActions: @escaping (CommandContext) -> [CommandCandidate],
    ) {
        self.providers = providers
        self.ranker = ranker
        self.now = now
        self.pristineActions = pristineActions
        candidates = Array(repeating: [], count: providers.count)
    }

    var selectedRow: CommandRow? {
        rows.first { $0.id == selectedRowID }
    }

    /// Nothing typed, and no ⌘L address.
    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pristineURL == nil
    }

    /// A new opening: `text`, with the ⌘L address `pristineURL` if any.
    func start(
        text newText: String,
        pristineURL newPristineURL: URL?,
        searchEngine engine: SearchEngine,
        context newContext: CommandContext,
    ) {
        cancelQuery()
        text = newText
        pristineURL = newPristineURL
        searchEngine = engine
        context = newContext
        candidates = Array(repeating: [], count: providers.count)
        refresh(resetSelection: true)
    }

    /// Settings changed while the bar is open: the engine and suggestions follow immediately. Suggestions already
    /// received are forgotten and the sources queried again.
    func apply(searchEngine engine: SearchEngine, context newContext: CommandContext) {
        guard engine != searchEngine || newContext != context else {
            return
        }
        searchEngine = engine
        context = newContext
        cancelQuery()
        if let last = candidates.indices.last {
            candidates[last] = []
        }
        refresh(resetSelection: false)
        startQuery(CommandQuery(text: text, searchEngine: searchEngine))
    }

    /// New field text: rows rebuilt right away, first row selected, then sources queried in a task.
    func updateText(_ newText: String) {
        guard newText != text else {
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

    /// Row run by Return (`rowID` nil: the selected row, otherwise the first one) or by a click on row `rowID`; nil
    /// for a clicked row gone in the meantime, never another one (review IU11).
    func row(for rowID: CommandRow.ID?) -> CommandRow? {
        if let rowID {
            return rows.first { $0.id == rowID }
        }
        return rows.first { $0.id == selectedRowID } ?? rows.first
    }

    /// The bar closes: everything is forgotten.
    func reset() {
        cancelQuery()
        text = ""
        rows = []
        selectedRowID = nil
        pristineURL = nil
        candidates = Array(repeating: [], count: providers.count)
    }

    /// Tests: waits for the current search to finish.
    func waitForPendingResults() async {
        await queryTask?.value
    }

    // MARK: Sources

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
        let immediate = providers.indices.filter { providers[$0].answersAtOnce }
        for index in immediate {
            candidates[index] = await providers[index].candidates(for: query, context: context)
        }
        guard !Task.isCancelled else {
            return
        }
        if !immediate.isEmpty {
            refresh(resetSelection: false)
        }
        await withTaskGroup(of: (index: Int, found: [CommandCandidate]).self) { group in
            for index in providers.indices where !providers[index].answersAtOnce {
                group.addTask { [self] in
                    await (index, ask(index, query, context: context))
                }
            }
            for await (index, found) in group {
                guard !Task.isCancelled else {
                    return
                }
                candidates[index] = found
                refresh(resetSelection: false)
            }
        }
    }

    /// Results of source `index`.
    private func ask(_ index: Int, _ query: CommandQuery, context: CommandContext) async -> [CommandCandidate] {
        await providers[index].candidates(for: query, context: context)
    }

    /// Recomputes the rows; the selection returns to the first row if requested or if the selected row has
    /// disappeared.
    private func refresh(resetSelection: Bool) {
        let query = CommandQuery(text: text, searchEngine: searchEngine)
        let newRows = if let pristineURL {
            ranker.pristineRows(currentURL: pristineURL, actions: pristineActions(context))
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
