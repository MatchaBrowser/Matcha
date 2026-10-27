import Foundation
@testable import Matcha
import Testing
import Translation

/// Translation sessions of a window (task 9.3): a queue of jobs per language pair, the pair's session run when a job
/// comes and again when one comes after it ended, the jobs failed when the window closes. The session itself is played
/// by the test (`takeJob`, `sessionDidEnd`).
@MainActor
struct TranslationHostTests {
    private let host = TranslationHost(languages: TranslationLanguages(preferred: ["fr"]))
    private let pair = TranslationHost.Pair(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "fr"))
    private let blocks = [TranslationBlock.make(1, ["Hello"])]

    /// Starts a translation of `blocks` and waits until its job is queued.
    private func start() async throws -> Task<[TranslationBlock.ID: [String]], any Error> {
        let task = Task { [host, pair, blocks] in try await host.translate(blocks, pair: pair) }
        try await waitUntil { host.configurations[pair] != nil }
        return task
    }

    @Test func `a job runs the session of its pair and gets its answer`() async throws {
        let task = try await start()
        #expect(host.pairs == [pair])
        let configuration = try #require(host.configurations[pair])
        #expect(configuration.source == pair.source)
        #expect(configuration.target == pair.target)

        let job = try #require(host.takeJob(for: pair))
        #expect(job.blocks == blocks)
        #expect(host.takeJob(for: pair)?.blocks == nil)
        job.continuation.resume(returning: [1: ["Bonjour"]])
        #expect(try await task.value == [1: ["Bonjour"]])
    }

    @Test func `a job after the session ended runs it again`() async throws {
        let first = try await start()
        let firstJob = try #require(host.takeJob(for: pair))
        firstJob.continuation.resume(returning: [:])
        _ = try await first.value
        let version = try #require(host.configurations[pair]?.version)
        host.sessionDidEnd(for: pair)
        #expect(host.configurations[pair]?.version == version)

        let second = Task { [host, pair, blocks] in try await host.translate(blocks, pair: pair) }
        try await waitUntil { host.configurations[pair]?.version != version }
        #expect(host.pairs == [pair])
        try #require(host.takeJob(for: pair)).continuation.resume(returning: [1: ["Salut"]])
        #expect(try await second.value == [1: ["Salut"]])
    }

    @Test func `a job that comes while the session runs waits for it`() async throws {
        let first = try await start()
        let version = try #require(host.configurations[pair]?.version)
        let firstJob = try #require(host.takeJob(for: pair))
        // A second job while the session runs: the same session takes it, it isn't run again.
        let second = Task { [host, pair, blocks] in try await host.translate(blocks, pair: pair) }
        var secondJob: TranslationHost.Job?
        try await waitUntil {
            secondJob = secondJob ?? host.takeJob(for: pair)
            return secondJob != nil
        }
        #expect(host.configurations[pair]?.version == version)
        firstJob.continuation.resume(returning: [:])
        try #require(secondJob).continuation.resume(returning: [2: ["x"]])
        _ = try await first.value
        #expect(try await second.value == [2: ["x"]])
    }

    @Test func `closing the window fails the jobs still waiting`() async throws {
        let task = try await start()
        host.cancelAll()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(host.takeJob(for: pair)?.blocks == nil)
    }
}
