import Foundation
@testable import Matcha
import Testing
import WebKit

/// Réponses de WebKit attendues avec un délai (tâche 5.6) : son des pages, captures.
@MainActor
struct CallbackTimeoutTests {
    @Test func `an answer in time is returned`() async {
        let value = await CallbackTimeout.value(timeout: .seconds(5), fallback: true) { done in
            done(false)
        }
        #expect(!value)
    }

    @Test func `an asynchronous answer in time is returned`() async {
        let value = await CallbackTimeout.value(timeout: .seconds(5), fallback: 0) { done in
            Task {
                try? await Task.sleep(for: .milliseconds(20))
                done(42)
            }
        }
        #expect(value == 42)
    }

    /// Une page qui ne répond pas est tenue pour occupée : elle ne se met pas en veille.
    @Test func `no answer gives the fallback after the timeout`() async {
        let start = ContinuousClock.now
        let value = await CallbackTimeout.value(timeout: .milliseconds(50), fallback: true) { _ in }
        #expect(value)
        #expect(ContinuousClock.now - start >= .milliseconds(50))
    }

    @Test func `a late answer is ignored`() async {
        var late: (@MainActor @Sendable (Bool) -> Void)?
        let value = await CallbackTimeout.value(timeout: .milliseconds(20), fallback: true) { done in
            late = done
        }
        #expect(value)
        // Ni plantage (continuation reprise deux fois) ni effet.
        late?(false)
        late?(false)
    }

    @Test func `a page without media is not playing`() async throws {
        let tab = BrowserTab(configuration: TestPages.configuration())
        tab.load(TestPages.url("silence"))
        try await waitUntil { tab.title == "silence" && !tab.isLoading }
        #expect(await !TabLifecycleProbes.isPlayingMedia(in: tab.loadedWebView))
    }
}
