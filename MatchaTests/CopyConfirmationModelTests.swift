import Foundation
@testable import Matcha
import Testing

/// Fake sleep: each call lasts until the test finishes it, in call order.
/// A task cancelled in the meantime then throws `CancellationError`, except with `ignoresCancellation`.
@MainActor
private final class SteppedSleep {
    /// Mimics a sleep that ignores cancellation: it finishes normally.
    var ignoresCancellation = false
    private(set) var durations: [Duration] = []
    /// Finished sleeps, and among them those whose task had been cancelled.
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

    /// Finishes the oldest sleep still in progress.
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

/// “URL Copied” confirmation: display, duration, restart and cancellation.
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

        // The first sleep finishes: cancelled, it hides nothing.
        sleeper.finishOldest()
        try await waitUntil { sleeper.finished == 1 }
        #expect(sleeper.cancelled == 1)
        #expect(model.isVisible)

        // The second one, complete, hides the confirmation.
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

        // The first sleep finishes without error despite the cancellation: the confirmation stays.
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
