import Foundation
import OSLog

/// Suggestions du moteur de recherche, demandées 150 ms après la dernière frappe : une frappe plus
/// récente annule la tâche, donc l'attente, et rien n'est envoyé. Seulement pour un texte lu comme
/// une recherche (et qui n'a pas l'air d'une adresse), réglage activé, hors fenêtre privée. Le texte
/// tapé n'est jamais journalisé.
@MainActor
final class SearchSuggestionsProvider: CommandProvider {
    typealias Fetch = @MainActor (String, SearchEngine) async throws -> [String]
    typealias Sleep = @MainActor (Duration) async throws -> Void

    /// Attente avant la demande.
    nonisolated static let delay = Duration.milliseconds(150)
    /// Au-delà, le texte n'est pas envoyé.
    nonisolated static let maximumLength = 120

    private let fetch: Fetch
    private let sleep: Sleep

    /// `fetch` et `sleep` sont remplacés dans les tests.
    init(
        fetch: @escaping Fetch = { try await SearchSuggestionClient.shared.suggestions(for: $0, engine: $1) },
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
    ) {
        self.fetch = fetch
        self.sleep = sleep
    }

    /// Vrai seulement si : suggestions permises (réglage et fenêtre non privée), texte lu comme une
    /// recherche qui ne ressemble pas à une adresse, 1 à 120 caractères.
    nonisolated static func allowsRequest(for query: CommandQuery, context: CommandContext) -> Bool {
        context.allowsSuggestions && query.isSearch && !looksLikeAddress(query)
            && (1 ... maximumLength).contains(query.trimmed.count)
    }

    /// Un seul mot avec « : », « / » ou « @ » : sans doute une adresse que `AddressResolver` lit comme
    /// une recherche (« intranet:8080 », « wiki/rh/salaires », une adresse e-mail). Elle ne part pas
    /// chez le moteur, même si Entrée la cherche.
    private nonisolated static func looksLikeAddress(_ query: CommandQuery) -> Bool {
        query.tokens.count == 1 && query.trimmed.contains { ":/@".contains($0) }
    }

    func candidates(for query: CommandQuery, context: CommandContext) async -> [CommandCandidate] {
        guard Self.allowsRequest(for: query, context: context) else {
            return []
        }
        do {
            try await sleep(Self.delay)
            try Task.checkCancellation()
            let texts = try await fetch(query.trimmed, query.searchEngine)
            return texts.map { CommandCandidate(kind: .suggestion, title: $0, url: nil) }
        } catch {
            Self.log(error, engine: query.searchEngine)
            return []
        }
    }

    /// Annulation (frappe suivante, barre fermée) : silencieuse. Le reste : la raison, jamais le texte
    /// ni l'adresse.
    private static func log(_ error: any Error, engine: SearchEngine) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return
        }
        let reason = reason(for: error)
        Logger.commandBar.debug("Suggestions indisponibles (\(engine.rawValue, privacy: .public)) : \(reason, privacy: .public)")
    }

    private static func reason(for error: any Error) -> String {
        switch error {
        case let SearchSuggestionError.status(code): "status \(code)"
        case SearchSuggestionError.tooLarge: "tooLarge"
        case SearchSuggestionError.malformed: "malformed"
        case let error as URLError: "URLError \(error.code.rawValue)"
        default: String(describing: type(of: error))
        }
    }
}
