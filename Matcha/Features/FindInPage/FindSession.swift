import Foundation
import Observation
import OSLog

/// Sens d'une recherche dans la page.
nonisolated enum FindDirection: Equatable, Sendable {
    case forward
    case backward
}

/// Résultat de la dernière recherche : rien à signaler, une occurrence trouvée (et sélectionnée), ou aucune.
nonisolated enum FindStatus: Equatable, Sendable {
    case idle
    case found
    case notFound
}

/// Ce qui cherche dans une page : l'onglet et sa vue web (`BrowserTab+Find`), un faux dans les tests.
@MainActor
protocol FindPerformer: AnyObject {
    /// Cherche `query` sans tenir compte de la casse, en repartant du début une fois au bout. Vrai si une occurrence
    /// est trouvée (elle est alors sélectionnée et montrée) ; nil si la page ne peut pas chercher (pas de vue web).
    func search(_ query: String, direction: FindDirection) async -> Bool?
    /// Désélectionne l'occurrence trouvée.
    func deselectMatch()
}

/// Recherche dans une page (tâche 5.3) : barre ouverte ou non, texte cherché, résultat. Chaque page a la sienne
/// (onglet, aperçu, mini-fenêtre) : elle suit la page d'un onglet à l'autre et se retrouve telle quelle au retour.
///
/// La frappe lance la recherche 150 ms après la dernière touche ; une frappe plus récente l'annule. Entrée, ⌘G et
/// ⇧⌘G cherchent tout de suite. WebKit garde l'occurrence sélectionnée quand le texte s'allonge (« p », « po »)
/// et passe à la suivante pour le même texte. Le texte cherché n'est jamais journalisé.
@MainActor
@Observable
final class FindSession {
    typealias Sleep = @MainActor (Duration) async throws -> Void

    /// Attente après une frappe.
    nonisolated static let typingDelay = Duration.milliseconds(150)

    private(set) var isPresented = false
    private(set) var query = ""
    /// `!query.isEmpty`, suivi à part : le menu (⌘G, ⇧⌘G) n'est pas recalculé à chaque frappe.
    private(set) var hasQuery = false
    private(set) var status = FindStatus.idle
    /// Incrémenté à chaque ⌘F : le champ prend le clavier et sélectionne son texte.
    private(set) var focusRequest = 0

    /// Page où chercher ; l'onglet qui possède la recherche.
    @ObservationIgnored weak var performer: (any FindPerformer)?
    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// Dernière demande de clavier servie par le champ : un champ recréé (retour sur l'onglet) ne reprend pas le
    /// clavier à la page.
    @ObservationIgnored private var servedFocusRequest = 0
    /// Une recherche a sélectionné une occurrence : la fermeture la désélectionne.
    @ObservationIgnored private var hasSelectedMatch = false

    /// `sleep` est remplacé dans les tests.
    init(sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    // MARK: Barre

    /// ⌘F : ouvre la barre, ou la garde ouverte ; dans les deux cas, le champ prend le clavier et sélectionne son
    /// texte (le dernier texte cherché dans cette page).
    func present() {
        if !isPresented {
            isPresented = true
            Logger.browser.debug("Recherche dans la page ouverte")
        }
        focusRequest += 1
    }

    /// Vrai une seule fois par demande de clavier (`present`) : au champ de la prendre.
    func takeFocusRequest() -> Bool {
        guard servedFocusRequest != focusRequest else {
            return false
        }
        servedFocusRequest = focusRequest
        return true
    }

    /// ⎋ et × : la barre se ferme, la recherche en attente est annulée et l'occurrence trouvée désélectionnée. Le
    /// texte reste pour ⌘G et la prochaine ouverture.
    func close() {
        guard isPresented else {
            return
        }
        cancelSearch()
        isPresented = false
        status = .idle
        if hasSelectedMatch {
            hasSelectedMatch = false
            performer?.deselectMatch()
        }
        Logger.browser.debug("Recherche dans la page fermée")
    }

    /// Page libérée (onglet déchargé, aperçu ou mini-fenêtre fermés) : tout est oublié, sans toucher à la page.
    func reset() {
        cancelSearch()
        isPresented = false
        setQuery("")
        status = .idle
        hasSelectedMatch = false
    }

    /// La page a changé d'adresse : le dernier résultat ne vaut plus. La barre et son texte restent.
    func pageDidChange() {
        status = .idle
        hasSelectedMatch = false
    }

    /// Le processus de la page s'est arrêté (tâche 5.7) : la recherche en attente est annulée et le résultat oublié,
    /// sans rien demander à la page (il n'y a plus d'occurrence sélectionnée). La barre et son texte restent : ⌘G
    /// cherche de nouveau dans la page rechargée.
    func pageDidTerminate() {
        cancelSearch()
        pageDidChange()
    }

    // MARK: Recherche

    /// Nouveau texte du champ : recherché vers l'avant après `typingDelay`, sauf s'il est vide.
    func updateQuery(_ text: String) {
        guard text != query else {
            return
        }
        setQuery(text)
        cancelSearch()
        guard !text.isEmpty else {
            status = .idle
            return
        }
        searchTask = Task { [weak self, sleep] in
            do {
                try await sleep(Self.typingDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.perform(text, direction: .forward)
        }
    }

    /// Entrée, ⌘G, bouton ⌄ : occurrence suivante.
    func findNext() {
        search(.forward)
    }

    /// ⇧Entrée, ⇧⌘G, bouton ⌃ : occurrence précédente.
    func findPrevious() {
        search(.backward)
    }

    /// Tests : attend la fin de la recherche en cours.
    func waitForPendingSearch() async {
        await searchTask?.value
    }

    /// Cherche tout de suite (la frappe en attente est annulée) ; barre fermée (⌘G), elle s'ouvre sans prendre le
    /// clavier. Rien sans texte.
    private func search(_ direction: FindDirection) {
        guard !query.isEmpty else {
            return
        }
        isPresented = true
        cancelSearch()
        let text = query
        searchTask = Task { [weak self] in
            await self?.perform(text, direction: direction)
        }
    }

    /// Résultat ignoré si une autre recherche a pris le relais, si le texte a changé ou si la barre est fermée.
    private func perform(_ text: String, direction: FindDirection) async {
        let found = await performer?.search(text, direction: direction)
        guard !Task.isCancelled, text == query, isPresented else {
            return
        }
        switch found {
        case .some(true):
            status = .found
            hasSelectedMatch = true
        case .some(false):
            status = .notFound
        case nil:
            status = .idle
        }
    }

    private func setQuery(_ text: String) {
        query = text
        if hasQuery == text.isEmpty {
            hasQuery = !text.isEmpty
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
    }
}
