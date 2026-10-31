import Foundation
import Observation
import Translation

/// Translation sessions of a window (browsing window or mini window; task 9.3). A session only comes from a SwiftUI
/// view (`translationTask`), the only way before macOS 26 and the only one that can ask to download the languages:
/// one hidden view per language pair (`TranslationSessionsView`). The pages ask for their blocks to be translated
/// (`translate`); the jobs wait in a queue per pair, and the pair's session runs them until the queue is empty, then
/// ends; a new job runs it again (`Configuration.invalidate`).
@MainActor
@Observable
final class TranslationHost {
    /// Languages of a session; no source: the framework recognizes it.
    struct Pair: Hashable, Identifiable, Sendable {
        let source: Locale.Language?
        let target: Locale.Language

        var id: Self {
            self
        }
    }

    /// Blocks to translate, and who waits for them.
    struct Job: Sendable {
        let blocks: [TranslationBlock]
        let continuation: CheckedContinuation<[TranslationBlock.ID: [String]], any Error>
    }

    let languages: TranslationLanguages
    /// Pairs with a hidden view, in the order they came.
    private(set) var pairs: [Pair] = []
    /// Configuration of each pair's view; changed to run its session again.
    private(set) var configurations: [Pair: TranslationSession.Configuration] = [:]
    @ObservationIgnored private var queues: [Pair: [Job]] = [:]
    /// Pairs whose session is running (or about to).
    @ObservationIgnored private var running: Set<Pair> = []

    init(languages: TranslationLanguages) {
        self.languages = languages
    }

    /// Translates `blocks` from `pair.source` into `pair.target`, by the session of the pair.
    func translate(_ blocks: [TranslationBlock], pair: Pair) async throws -> [TranslationBlock.ID: [String]] {
        try await withCheckedThrowingContinuation { continuation in
            queues[pair, default: []].append(Job(blocks: blocks, continuation: continuation))
            wake(pair)
        }
    }

    /// Next job of `pair`, for its session; nil: none left.
    func takeJob(for pair: Pair) -> Job? {
        guard var queue = queues[pair], !queue.isEmpty else {
            return nil
        }
        let job = queue.removeFirst()
        queues[pair] = queue
        return job
    }

    /// The session of `pair` has run out of jobs and ends; a job that came meanwhile runs it again.
    func sessionDidEnd(for pair: Pair) {
        running.remove(pair)
        if queues[pair]?.isEmpty == false {
            wake(pair)
        }
    }

    /// The window closes: its sessions go with it, and the jobs still waiting fail.
    func cancelAll() {
        let jobs = queues.values.flatMap(\.self)
        queues = [:]
        running = []
        for job in jobs {
            job.continuation.resume(throwing: CancellationError())
        }
    }

    private func wake(_ pair: Pair) {
        guard !running.contains(pair) else {
            return
        }
        running.insert(pair)
        if var configuration = configurations[pair] {
            configuration.invalidate()
            configurations[pair] = configuration
        } else {
            configurations[pair] = TranslationStrategy.configuration(source: pair.source, target: pair.target)
            pairs.append(pair)
        }
    }
}

/// The page menu's “Translate to …” (task 9.3).
extension TranslationHost: PageTranslationHosting {
    var targetLanguage: Locale.Language? {
        languages.target
    }

    var languageChoices: [Locale.Language] {
        languages.choices
    }

    func translate(_ page: BrowserTab, into language: Locale.Language?) {
        PageTranslationActions.translate(page, host: self, into: language)
    }

    func showOriginal(_ page: BrowserTab) {
        PageTranslationActions.showOriginal(page)
    }
}
