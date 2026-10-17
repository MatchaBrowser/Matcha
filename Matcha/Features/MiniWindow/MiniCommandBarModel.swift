import Foundation
import Observation
import OSLog

/// Ce que la barre d'une mini-fenêtre est en train de faire.
nonisolated enum MiniCommandBarMode: Equatable, Sendable {
    /// ⌥⌘N, ⌘T : saisie neuve, la page de la mini-fenêtre sera remplacée.
    case newSearch
    /// ⌘L, clic sur l'adresse : l'adresse de la page, sélectionnée.
    case editAddress
}

/// Suite donnée à Entrée ou à un clic sur une ligne de la barre d'une mini-fenêtre.
nonisolated enum MiniCommandBarSubmission: Equatable, Sendable {
    /// Charger l'adresse dans la mini-fenêtre.
    case load(URL)
    /// Copier l'adresse de la page.
    case copyURL
    /// Rien à faire : la barre reste ouverte.
    case ignore
}

/// Barre de commande d'une mini-fenêtre : le texte tapé (adresse ou recherche), l'historique et les
/// suggestions du moteur, jamais d'onglets ni d'actions (la mini-fenêtre n'a qu'une page). Même
/// déroulé que `CommandBarModel` : lignes reconstruites à chaque frappe, puis une tâche interroge
/// l'historique puis les suggestions.
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

    /// Page de la mini-fenêtre.
    @ObservationIgnored let tab: BrowserTab
    @ObservationIgnored private let faviconService: FaviconService
    /// Historique puis suggestions (toujours en dernier).
    @ObservationIgnored private let providers: [any CommandProvider]
    @ObservationIgnored private let ranker: CommandRanker
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var context = CommandContext()
    @ObservationIgnored private var candidates: [[CommandCandidate]]
    /// Adresse de ⌘L tant que le texte n'a pas été modifié.
    @ObservationIgnored private var pristineURL: URL?
    @ObservationIgnored private var queryTask: Task<Void, Never>?

    /// Sans effet de bord : rien n'est lancé avant la première ouverture.
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

    /// Icône du champ : celle du site quand on modifie l'adresse de la page.
    var editedTab: BrowserTab? {
        mode == .editAddress && tab.url != nil ? tab : nil
    }

    /// Aucune ligne d'onglet dans cette barre.
    var rowIcons: CommandRowIcons {
        CommandRowIcons(faviconService: faviconService) { _ in nil }
    }

    // MARK: Ouverture

    /// Déjà ouverte dans le même mode : le texte reste, le champ reprend seulement le clavier.
    /// `.editAddress` sans page revient à `.newSearch`.
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

    /// Réglages modifiés pendant que la barre est ouverte : moteur et suggestions suivent aussitôt.
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

    // MARK: Saisie et sélection

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

    /// Suite à donner à Entrée (`rowID` nil : la ligne sélectionnée) ou à un clic sur une ligne.
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

    /// Tests : attend la fin de la recherche en cours.
    func waitForPendingResults() async {
        await queryTask?.value
    }

    // MARK: Résultats

    /// Jamais privée : une mini-fenêtre utilise toujours le profil d'un Space.
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

    /// « Copier l'URL », la seule action de la barre d'une mini-fenêtre (lignes de ⌘L non modifié).
    private static var copyURLCandidate: CommandCandidate {
        CommandCandidate(
            kind: .action(.copyURL, keywords: CommandActionID.copyURL.keywords),
            title: CommandActionID.copyURL.title,
            url: nil,
        )
    }
}
