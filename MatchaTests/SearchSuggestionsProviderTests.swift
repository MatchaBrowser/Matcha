import Foundation
@testable import Matcha
import Testing

/// Source of the search engine's suggestions: delay, cancellation, policy and errors.
@MainActor
struct SearchSuggestionsProviderTests {
    private let engine = FakeSuggestionEngine()
    private let sleeper = FakeSleep()
    private let context = CommandContext(isPrivate: false, showsSearchSuggestions: true)

    private var provider: SearchSuggestionsProvider {
        engine.provider { [sleeper] in try await sleeper.sleep($0) }
    }

    @Test func `suggestions wait 150 ms then fetch the trimmed text`() async {
        engine.responses["pain au"] = ["pain au levain"]
        let candidates = await provider.candidates(for: query("  pain au "), context: context)
        #expect(sleeper.durations == [.milliseconds(150)])
        #expect(engine.requests == ["pain au"])
        #expect(candidates == [CommandCandidate(kind: .suggestion, title: "pain au levain", url: nil)])
    }

    @Test func `suggestions keep the engine order`() async {
        engine.responses["pain"] = ["pain perdu", "pain au levain", "pain de mie"]
        let candidates = await provider.candidates(for: query("pain"), context: context)
        #expect(candidates.map(\.title) == ["pain perdu", "pain au levain", "pain de mie"])
        #expect(candidates.allSatisfy { $0.kind == .suggestion && $0.url == nil })
    }

    @Test func `suggestions are never fetched when not allowed`() async {
        let refused = [
            (query("pain"), CommandContext(isPrivate: false, showsSearchSuggestions: false)),
            (query("pain"), CommandContext(isPrivate: true, showsSearchSuggestions: true)),
            (query("apple.com"), context),
            (query(" "), context),
        ]
        for (refusedQuery, refusedContext) in refused {
            #expect(await provider.candidates(for: refusedQuery, context: refusedContext).isEmpty)
        }
        #expect(sleeper.durations.isEmpty)
        #expect(engine.requests.isEmpty)
    }

    @Test func `a cancelled wait fetches nothing`() async {
        sleeper.error = CancellationError()
        #expect(await provider.candidates(for: query("pain"), context: context).isEmpty)
        #expect(engine.requests.isEmpty)

        // With the real delay: a task cancelled during the 150 ms sends nothing.
        let realWait = engine.provider(sleep: nil)
        let task = Task { await realWait.candidates(for: query("pain"), context: context) }
        task.cancel()
        #expect(await task.value.isEmpty)
        #expect(engine.requests.isEmpty)
    }

    /// Review A7: the engine chosen for suggestions is asked, the search engine otherwise.
    @Test func `suggestions come from the engine chosen for them`() async {
        _ = await provider.candidates(for: query("pain", engine: .google), context: context)
        var chosen = context
        chosen.suggestionEngine = .duckDuckGo
        _ = await provider.candidates(for: query("pain", engine: .google), context: chosen)
        #expect(engine.engines == [.google, .duckDuckGo])
    }

    @Test func `fetch errors give no suggestions`() async {
        for error: any Error in [URLError(.timedOut), SearchSuggestionError.status(503), SearchSuggestionError.malformed] {
            engine.error = error
            #expect(await provider.candidates(for: query("pain"), context: context).isEmpty)
        }
        #expect(engine.requests.count == 3)
    }
}
