import Foundation
import Observation
import OSLog

/// What the bar of a mini window is currently doing.
nonisolated enum MiniCommandBarMode: Equatable, Sendable {
    /// ⌥⌘N, ⌘T: fresh input, the mini window's page will be replaced.
    case newSearch
    /// ⌘L, click on the address: the page's address, selected.
    case editAddress
}

/// What follows Return or a click on a row of a mini window's bar.
nonisolated enum MiniCommandBarSubmission: Equatable, Sendable {
    /// Load the address in the mini window.
    case load(URL)
    /// Copy the page's address.
    case copyURL
    /// Nothing to do: the bar stays open.
    case ignore
}

/// Command bar of a mini window: the typed text (address or search), the history and the
/// engine's suggestions, never tabs or actions (the mini window has only one page). Same
/// flow as `CommandBarModel`: rows rebuilt on each keystroke, then a task queries
/// the history, then the suggestions.
@MainActor
@Observable
final class MiniCommandBarModel: CommandBarPanelModel {
    private(set) var isPresented = false
    private(set) var mode = MiniCommandBarMode.newSearch
    private(set) var text = ""
    private(set) var rows: [CommandRow] = []
    private(set) var selectedRowID: CommandRow.ID?
    private(set) var focusRequest = 0
    private(set) var searchEngine = SearchEngine.defaultEngine

    /// The mini window's page.
    @ObservationIgnored let tab: BrowserTab
    @ObservationIgnored private let faviconService: FaviconService
    /// History, then suggestions (always last).
    @ObservationIgnored private let providers: [any CommandProvider]
    @ObservationIgnored private let ranker: CommandRanker
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var context = CommandContext()
    @ObservationIgnored private var candidates: [[CommandCandidate]]
    /// Address from ⌘L as long as the text has not been edited.
    @ObservationIgnored private var pristineURL: URL?
    @ObservationIgnored private var queryTask: Task<Void, Never>?

    /// Free of side effects: nothing is started before the first opening.
    init(
        tab: BrowserTab,
        faviconService: FaviconService,
        history: (any HistorySource)? = nil,
        suggestions: SearchSuggestionsProvider = SearchSuggestionsProvider(),
        ranker: CommandRanker = CommandRanker(),
        now: @escaping () -> Date = { .now },
    ) {
        self.tab = tab
        self.faviconService = faviconService
        providers = [HistoryProvider(source: history), suggestions]
        self.ranker = ranker
        self.now = now
        candidates = Array(repeating: [], count: providers.count)
    }

    var selectedRow: CommandRow? {
        rows.first { $0.id == selectedRowID }
    }

    /// Icon of the field: the site's icon when editing the page's address.
    var editedTab: BrowserTab? {
        mode == .editAddress && tab.url != nil ? tab : nil
    }

    /// No tab row in this bar.
    var rowIcons: CommandRowIcons {
        CommandRowIcons(faviconService: faviconService) { _ in nil }
    }

    // MARK: Opening

    /// Already open in the same mode: the text stays, the field only takes the keyboard back.
    /// `.editAddress` without a page falls back to `.newSearch`.
    func present(_ requested: MiniCommandBarMode, settings: CommandBarSettings) {
        let newMode = tab.url == nil ? .newSearch : requested
        focusRequest += 1
        if isPresented, newMode == mode {
            apply(settings)
            return
        }
        cancelQuery()
        mode = newMode
        pristineURL = newMode == .editAddress ? tab.url : nil
        text = pristineURL?.absoluteString ?? ""
        searchEngine = settings.searchEngine
        context = makeContext(settings)
        candidates = Array(repeating: [], count: providers.count)
        isPresented = true
        refresh(resetSelection: true)
        Logger.miniWindow.debug("Barre de la mini-fenêtre ouverte")
    }

    /// Settings changed while the bar is open: engine and suggestions follow immediately.
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

    // MARK: Input and selection

    func updateText(_ newText: String) {
        guard isPresented, newText != text else {
            return
        }
        text = newText
        pristineURL = nil
        cancelQuery()
        let query = CommandQuery(text: newText, searchEngine: searchEngine)
        if let last = candidates.indices.last {
            candidates[last] = CommandRanker.carriedOver(candidates[last], to: query)
        }
        refresh(resetSelection: true)
        startQuery(query)
    }

    func moveSelection(by delta: Int) {
        guard !rows.isEmpty else {
            return
        }
        let current = rows.firstIndex { $0.id == selectedRowID } ?? 0
        selectedRowID = rows[min(max(current + delta, 0), rows.count - 1)].id
    }

    /// What follows Return (`rowID` nil: the selected row) or a click on a row.
    func submission(for rowID: CommandRow.ID?) -> MiniCommandBarSubmission {
        guard isPresented else {
            return .ignore
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, pristineURL == nil {
            return .ignore
        }
        let id = rowID ?? selectedRowID
        guard let row = rows.first(where: { $0.id == id }) ?? rows.first else {
            return .ignore
        }
        switch row.target {
        case let .open(url): return .load(url)
        case .perform(.copyURL): return .copyURL
        case .perform, .switchToTab: return .ignore
        }
    }

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
        mode = .newSearch
    }

    /// Tests: waits for the current search to finish.
    func waitForPendingResults() async {
        await queryTask?.value
    }

    // MARK: Results

    /// Never private: a mini window always uses the profile of a Space.
    private func makeContext(_ settings: CommandBarSettings) -> CommandContext {
        CommandContext(isPrivate: false, showsSearchSuggestions: settings.showsSearchSuggestions)
    }

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

    private func refresh(resetSelection: Bool) {
        let query = CommandQuery(text: text, searchEngine: searchEngine)
        let newRows = if let pristineURL {
            ranker.pristineRows(currentURL: pristineURL, actions: [Self.copyURLCandidate])
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

    /// “Copy URL”, the only action of a mini window's bar (rows of an unedited ⌘L).
    private static var copyURLCandidate: CommandCandidate {
        CommandCandidate(
            kind: .action(.copyURL, keywords: CommandActionID.copyURL.keywords),
            title: CommandActionID.copyURL.title,
            url: nil,
        )
    }
}
