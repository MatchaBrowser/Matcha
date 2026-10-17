import Foundation
import Observation
import OSLog

/// État de la barre de commande d'une fenêtre : ouverture, mode, texte, lignes et sélection.
///
/// Chaque frappe reconstruit les lignes tout de suite (lignes du texte, puis résultats déjà reçus,
/// reclassés), puis une seule tâche interroge les sources dans l'ordre : onglets, actions,
/// historique, suggestions. Les lignes sont republiées après chaque source ; une frappe plus récente
/// annule la tâche en cours.
@MainActor
@Observable
final class CommandBarModel {
    private(set) var isPresented = false
    private(set) var mode = CommandBarMode.newTab
    private(set) var text = ""
    private(set) var rows: [CommandRow] = []
    private(set) var selectedRowID: CommandRow.ID?
    /// Incrémenté à chaque demande d'ouverture : le champ reprend le clavier et sélectionne tout.
    private(set) var focusRequest = 0
    /// Moteur de l'ouverture en cours (sous-titres « Rechercher sur … »).
    private(set) var searchEngine = SearchEngine.defaultEngine

    @ObservationIgnored let windowModel: WindowModel
    @ObservationIgnored private let actions: ActionsProvider
    /// Onglets, actions, historique, suggestions (toujours en dernier).
    @ObservationIgnored private let providers: [any CommandProvider]
    @ObservationIgnored private let ranker: CommandRanker
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var context = CommandContext()
    /// Résultats reçus, un tableau par source.
    @ObservationIgnored private var candidates: [[CommandCandidate]]
    /// Adresse de ⌘L tant que le texte n'a pas été modifié.
    @ObservationIgnored private var pristineURL: URL?
    @ObservationIgnored private var queryTask: Task<Void, Never>?

    /// Sans effet de bord : rien n'est lancé avant la première ouverture.
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

    // MARK: Ouverture

    /// ⌘T et « Nouvel onglet » : la barre en mode nouvel onglet. Avec une page d'accueil pour les
    /// nouveaux onglets, l'onglet est créé tout de suite et la barre s'ouvre sur son adresse.
    func newTab(_ settings: CommandBarSettings) {
        if let home = settings.newTabHomeURL {
            let tab = windowModel.space.tabManager.newTab(url: home)
            present(.currentTab(tab.id), text: home.absoluteString, pristineURL: home, settings: settings)
        } else {
            present(.newTab, text: "", pristineURL: nil, settings: settings)
        }
    }

    /// ⌘L et la pastille d'adresse : édition de l'onglet affiché, ou nouvel onglet s'il n'y en a pas.
    func editCurrentTab(_ settings: CommandBarSettings) {
        if let tab = windowModel.space.tabManager.selectedTab {
            present(.currentTab(tab.id), text: tab.url?.absoluteString ?? "", pristineURL: tab.url, settings: settings)
        } else {
            present(.newTab, text: "", pristineURL: nil, settings: settings)
        }
    }

    /// Réglages modifiés pendant que la barre est ouverte (fenêtre Réglages, barre restée ouverte) :
    /// le moteur et les suggestions suivent aussitôt. Les suggestions déjà reçues sont oubliées et
    /// les sources interrogées de nouveau.
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

    /// Déjà ouverte dans le même mode : le texte reste, le champ reprend seulement le clavier.
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
        Logger.commandBar.debug("Barre ouverte")
    }

    // MARK: Saisie et sélection

    /// Nouveau texte du champ : lignes reconstruites tout de suite, première ligne sélectionnée, puis
    /// sources interrogées dans une tâche.
    func updateText(_ newText: String) {
        guard isPresented, newText != text else {
            return
        }
        text = newText
        // La première modification met fin pour de bon à l'adresse de ⌘L.
        pristineURL = nil
        cancelQuery()
        let query = CommandQuery(text: newText, searchEngine: searchEngine)
        if let last = candidates.indices.last {
            candidates[last] = CommandRanker.carriedOver(candidates[last], to: query)
        }
        refresh(resetSelection: true)
        startQuery(query)
    }

    /// Déplace la sélection, bornée aux lignes, sans boucler.
    func moveSelection(by delta: Int) {
        guard !rows.isEmpty else {
            return
        }
        let current = rows.firstIndex { $0.id == selectedRowID } ?? 0
        selectedRowID = rows[min(max(current + delta, 0), rows.count - 1)].id
    }

    /// Suite à donner à Entrée (`rowID` nil : la ligne sélectionnée) ou à un clic sur une ligne.
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

    /// Ferme la barre et oublie tout, sauf `focusRequest`.
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
        Logger.commandBar.debug("Barre fermée")
    }

    /// Tests : attend la fin de la recherche en cours.
    func waitForPendingResults() async {
        await queryTask?.value
    }

    // MARK: Résultats

    private func makeContext(_ settings: CommandBarSettings) -> CommandContext {
        CommandContext(isPrivate: windowModel.session.isPrivate, showsSearchSuggestions: settings.showsSearchSuggestions)
    }

    /// Interroge les sources dans une tâche, sauf pour un texte vide ou l'adresse de ⌘L non modifiée.
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

    /// Recalcule les lignes ; la sélection revient à la première ligne si demandé ou si la ligne
    /// sélectionnée a disparu.
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
