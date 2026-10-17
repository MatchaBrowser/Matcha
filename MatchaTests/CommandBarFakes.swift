import Foundation
@testable import Matcha

// Sources factices de la barre de commande.

/// Adresse `about:blank?<name>` : WebKit la garde telle quelle, sans réseau.
func blankPage(_ name: String) -> URL {
    URL(string: "about:blank?\(name)")!
}

/// Historique factice : renvoie `entries` et note chaque lecture.
@MainActor
final class FakeHistory: HistorySource {
    var entries: [HistoryEntry]
    private(set) var requests: [(text: String, limit: Int)] = []

    init(entries: [HistoryEntry] = []) {
        self.entries = entries
    }

    func entries(matching query: CommandQuery, limit: Int) async -> [HistoryEntry] {
        requests.append((query.text, limit))
        return entries
    }
}

/// Moteur de suggestions factice : note chaque texte demandé et répond `responses[texte]` (sinon
/// rien), ou lève `error`. Un texte de `suspended` attend `resume(_:with:)`.
@MainActor
final class FakeSuggestionEngine {
    private(set) var requests: [String] = []
    var responses: [String: [String]] = [:]
    var error: (any Error)?
    var suspended: Set<String> = []
    private var waiting: [String: CheckedContinuation<[String], Never>] = [:]

    func fetch(_ text: String, _: SearchEngine) async throws -> [String] {
        requests.append(text)
        if let error {
            throw error
        }
        if suspended.contains(text) {
            return await withCheckedContinuation { waiting[text] = $0 }
        }
        return responses[text] ?? []
    }

    func isWaiting(for text: String) -> Bool {
        waiting[text] != nil
    }

    func resume(_ text: String, with suggestions: [String]) {
        waiting.removeValue(forKey: text)?.resume(returning: suggestions)
    }

    /// Libère les demandes encore en attente (fin de test).
    func resumeAll() {
        for text in waiting.keys {
            resume(text, with: [])
        }
    }

    /// Source branchée sur ce moteur ; `sleep` nil : la vraie attente de 150 ms.
    func provider(sleep: SearchSuggestionsProvider.Sleep? = { _ in }) -> SearchSuggestionsProvider {
        let fetch: SearchSuggestionsProvider.Fetch = { [self] text, engine in try await self.fetch(text, engine) }
        guard let sleep else {
            return SearchSuggestionsProvider(fetch: fetch)
        }
        return SearchSuggestionsProvider(fetch: fetch, sleep: sleep)
    }
}

/// Attente factice : note chaque durée demandée, puis rend la main aussitôt ou lève `error`.
@MainActor
final class FakeSleep {
    private(set) var durations: [Duration] = []
    var error: (any Error)?

    func sleep(_ duration: Duration) async throws {
        durations.append(duration)
        if let error {
            throw error
        }
    }
}

/// Attente factice qui dure jusqu'à `open()` ; une tâche annulée entre-temps lève alors `CancellationError`.
@MainActor
final class GatedSleep {
    private var waiting: [CheckedContinuation<Void, Never>] = []

    var waitingCount: Int {
        waiting.count
    }

    func sleep(_: Duration) async throws {
        await withCheckedContinuation { waiting.append($0) }
        try Task.checkCancellation()
    }

    func open() {
        let released = waiting
        waiting = []
        released.forEach { $0.resume() }
    }
}
