import Foundation
import OSLog

/// Search engine suggestions, requested 150 ms after the last keystroke: a more recent keystroke cancels the task,
/// hence the wait, and nothing is sent. Only for a text read as a search (and that does not look like an address),
/// setting enabled, outside a private window; from the engine chosen for suggestions, otherwise the search engine
/// (review A7). The typed text is never logged.
@MainActor
final class SearchSuggestionsProvider: CommandProvider {
    typealias Fetch = @MainActor (String, SearchEngine) async throws -> [String]
    typealias Sleep = @MainActor (Duration) async throws -> Void

    /// Wait before the request.
    nonisolated static let delay = Duration.milliseconds(150)
    /// Beyond this, the text is not sent.
    nonisolated static let maximumLength = 120

    private let fetch: Fetch
    private let sleep: Sleep

    /// `fetch` and `sleep` are replaced in tests; by default, a client of its own (a bar's: no shared state).
    init(
        fetch: Fetch? = nil,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
    ) {
        if let fetch {
            self.fetch = fetch
        } else {
            let client = SearchSuggestionClient()
            self.fetch = { try await client.suggestions(for: $0, engine: $1) }
        }
        self.sleep = sleep
    }

    /// True only if: suggestions allowed (setting and non-private window), text read as a search that does not
    /// look like an address, 1 to 120 characters.
    nonisolated static func allowsRequest(for query: CommandQuery, context: CommandContext) -> Bool {
        context.allowsSuggestions && query.isSearch && !looksLikeAddress(query)
            && (1 ... maximumLength).contains(query.trimmed.count)
    }

    /// A single word with “:”, “/” or “@”: probably an address that `AddressResolver` reads as a search
    /// (“intranet:8080”, “wiki/hr/salaries”, an email address). It is not sent to the engine, even if Return
    /// searches it.
    private nonisolated static func looksLikeAddress(_ query: CommandQuery) -> Bool {
        query.tokens.count == 1 && query.trimmed.contains { ":/@".contains($0) }
    }

    func candidates(for query: CommandQuery, context: CommandContext) async -> [CommandCandidate] {
        guard Self.allowsRequest(for: query, context: context) else {
            return []
        }
        let engine = context.suggestionEngine ?? query.searchEngine
        do {
            try await sleep(Self.delay)
            try Task.checkCancellation()
            let texts = try await fetch(query.trimmed, engine)
            return texts.map { CommandCandidate(kind: .suggestion, title: $0, url: nil) }
        } catch {
            Self.log(error, engine: engine)
            return []
        }
    }

    /// Cancellation (next keystroke, bar closed): silent. Anything else: the reason, never the text or the address.
    private static func log(_ error: any Error, engine: SearchEngine) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return
        }
        let reason = reason(for: error)
        Logger.commandBar.debug("Suggestions unavailable (\(engine.rawValue, privacy: .public)): \(reason, privacy: .public)")
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
