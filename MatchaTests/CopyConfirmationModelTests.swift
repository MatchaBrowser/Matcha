import Foundation
@testable import Matcha
import Testing

/// Attente factice : chaque appel dure jusqu'à ce que le test le termine, dans l'ordre des appels.
/// Une tâche annulée entre-temps lève alors `CancellationError`, sauf avec `ignoresCancellation`.
@MainActor
private final class SteppedSleep {
    /// Imite une attente qui ignore l'annulation : elle se termine normalement.
    var ignoresCancellation = false
    private(set) var durations: [Duration] = []
    /// Attentes terminées, et parmi elles celles dont la tâche avait été annulée.
    private(set) var finished = 0
    private(set) var cancelled = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    var waitingCount: Int {
        waiting.count
    }

    func sleep(_ duration: Duration) async throws {
        durations.append(duration)
        await withCheckedContinuation { waiting.append($0) }
        finished += 1
        if Task.isCancelled {
            cancelled += 1
            if !ignoresCancellation {
                throw CancellationError()
            }
        }
    }

    /// Termine la plus ancienne attente encore en cours.
    func finishOldest() {
        guard !waiting.isEmpty else {
            return
        }
        waiting.removeFirst().resume()
    }

    func finishAll() {
        while !waiting.isEmpty {
            finishOldest()
        }
    }
}

/// Confirmation « URL copiée » : affichage, durée, relance et annulation.
@MainActor
struct CopyConfirmationModelTests {
    private let sleeper = SteppedSleep()
    private let model: CopyConfirmationModel

    init() {
        model = CopyConfirmationModel { [sleeper] in try await sleeper.sleep($0) }
    }

    @Test func `hidden until a copy`() {
        #expect(!model.isVisible)
        #expect(model.presentationCount == 0)
    }

    @Test func `shows at once then hides after the delay`() async throws {
        model.show()
        #expect(model.isVisible)
        #expect(model.presentationCount == 1)
        try await waitUntil { sleeper.waitingCount == 1 }
        #expect(sleeper.durations == [.milliseconds(1500)])
        #expect(model.isVisible)

        sleeper.finishOldest()
        try await waitUntil { !model.isVisible }
        #expect(sleeper.cancelled == 0)
    }

    @Test func `a new copy while visible restarts the delay`() async throws {
        model.show()
        try await waitUntil { sleeper.waitingCount == 1 }
        model.show()
        #expect(model.presentationCount == 2)
        try await waitUntil { sleeper.waitingCount == 2 }

        // La première attente se termine : annulée, elle ne masque rien.
        sleeper.finishOldest()
        try await waitUntil { sleeper.finished == 1 }
        #expect(sleeper.cancelled == 1)
        #expect(model.isVisible)

        // La seconde, complète, masque la confirmation.
        sleeper.finishOldest()
        try await waitUntil { !model.isVisible }
        #expect(sleeper.durations == [.milliseconds(1500), .milliseconds(1500)])
    }

    @Test func `a cancelled delay that ignores cancellation hides nothing`() async throws {
        sleeper.ignoresCancellation = true
        model.show()
        try await waitUntil { sleeper.waitingCount == 1 }
        model.show()
        try await waitUntil { sleeper.waitingCount == 2 }

        // La première attente se termine sans erreur malgré l'annulation : la confirmation reste.
        sleeper.finishOldest()
        try await waitUntil { sleeper.finished == 1 }
        #expect(sleeper.cancelled == 1)
        #expect(model.isVisible)

        sleeper.finishOldest()
        try await waitUntil { !model.isVisible }
    }

    @Test func `cancel hides at once and stops the delay`() async throws {
        model.show()
        try await waitUntil { sleeper.waitingCount == 1 }
        model.cancel()
        #expect(!model.isVisible)

        sleeper.finishAll()
        try await waitUntil { sleeper.finished == 1 }
        #expect(sleeper.cancelled == 1)
        #expect(!model.isVisible)
    }

    @Test func `shows again after being hidden`() async throws {
        model.show()
        try await waitUntil { sleeper.waitingCount == 1 }
        sleeper.finishOldest()
        try await waitUntil { !model.isVisible }

        model.show()
        #expect(model.isVisible)
        #expect(model.presentationCount == 2)
        try await waitUntil { sleeper.waitingCount == 1 }
        sleeper.finishOldest()
        try await waitUntil { !model.isVisible }
    }
}
