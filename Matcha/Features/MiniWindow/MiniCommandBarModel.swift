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

/// Command bar of a mini window: the typed text (address or search), the history and the engine's suggestions, never
/// tabs or actions (the mini window has only one page). Same flow as `CommandBarModel`, through `CommandBarResults`.
@MainActor
@Observable
final class MiniCommandBarModel: CommandBarPanelModel {
    private(set) var isPresented = false
    private(set) var mode = MiniCommandBarMode.newSearch
    private(set) var focusRequest = 0

    /// The mini window's page.
    @ObservationIgnored let tab: BrowserTab
    @ObservationIgnored private let faviconService: FaviconService
    @ObservationIgnored let results: CommandBarResults

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
        // History, then suggestions; “Copy URL”, the only action, under an unmodified ⌘L address.
        results = CommandBarResults(
            providers: [HistoryProvider(source: history), suggestions],
            ranker: ranker,
            now: now,
            pristineActions: { _ in [Self.copyURLCandidate] },
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

    var searchEngine: SearchEngine {
        results.searchEngine
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
        mode = newMode
        let pristineURL = newMode == .editAddress ? tab.url : nil
        results.start(
            text: pristineURL?.absoluteString ?? "",
            pristineURL: pristineURL,
            searchEngine: settings.searchEngine,
            context: Self.context(settings),
        )
        isPresented = true
        Logger.miniWindow.debug("Mini window bar opened")
    }

    /// Settings changed while the bar is open: engine and suggestions follow immediately.
    func apply(_ settings: CommandBarSettings) {
        guard isPresented else {
            return
        }
        results.apply(searchEngine: settings.searchEngine, context: Self.context(settings))
    }

    /// Never private: a mini window always uses the profile of a Space.
    private static func context(_ settings: CommandBarSettings) -> CommandContext {
        CommandContext(isPrivate: false, showsSearchSuggestions: settings.showsSearchSuggestions)
    }

    // MARK: Input and selection

    func updateText(_ newText: String) {
        if isPresented {
            results.updateText(newText)
        }
    }

    func moveSelection(by delta: Int) {
        results.moveSelection(by: delta)
    }

    /// What follows Return (`rowID` nil: the selected row) or a click on a row.
    func submission(for rowID: CommandRow.ID?) -> MiniCommandBarSubmission {
        guard isPresented, !results.isBlank, let row = results.row(for: rowID) else {
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
        results.reset()
        isPresented = false
        mode = .newSearch
    }

    /// Tests: waits for the current search to finish.
    func waitForPendingResults() async {
        await results.waitForPendingResults()
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
