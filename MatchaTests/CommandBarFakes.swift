import Foundation
@testable import Matcha

// Fake sources for the command bar.

/// Address `about:blank?<name>`: WebKit keeps it as is, without any network access.
func blankPage(_ name: String) -> URL {
    URL(string: "about:blank?\(name)")!
}

/// Fake history: returns `entries` and records each read.
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

/// History that answers only on `resume(with:)`: a slow read of a large history.
@MainActor
final class HeldHistory: HistorySource {
    private var waiting: [CheckedContinuation<[HistoryEntry], Never>] = []

    var isWaiting: Bool {
        !waiting.isEmpty
    }

    func entries(matching _: CommandQuery, limit _: Int) async -> [HistoryEntry] {
        await withCheckedContinuation { waiting.append($0) }
    }

    func resume(with entries: [HistoryEntry]) {
        waiting.forEach { $0.resume(returning: entries) }
        waiting = []
    }
}

/// Fake suggestion engine: records each requested text and answers `responses[text]` (otherwise
/// nothing), or throws `error`. A text in `suspended` waits for `resume(_:with:)`.
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

    /// Releases the requests still pending (end of test).
    func resumeAll() {
        for text in waiting.keys {
            resume(text, with: [])
        }
    }

    /// Source plugged into this engine; `sleep` nil: the real 150 ms wait.
    func provider(sleep: SearchSuggestionsProvider.Sleep? = { _ in }) -> SearchSuggestionsProvider {
        let fetch: SearchSuggestionsProvider.Fetch = { [self] text, engine in try await self.fetch(text, engine) }
        guard let sleep else {
            return SearchSuggestionsProvider(fetch: fetch)
        }
        return SearchSuggestionsProvider(fetch: fetch, sleep: sleep)
    }
}

/// Fake sleep: records each requested duration, then returns immediately or throws `error`.
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

/// Fake sleep that lasts until `open()`; a task cancelled in the meantime then throws `CancellationError`.
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
