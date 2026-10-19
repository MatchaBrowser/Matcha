import Foundation

/// Waits at most `timeout` for the answer of a callback API (WebKit): without an answer in time, `fallback`. An answer
/// that arrives after the deadline is ignored. The callback may never come (page process stuck).
@MainActor
enum CallbackTimeout {
    static func value<Value: Sendable>(
        timeout: Duration,
        fallback: Value,
        _ start: (@escaping @MainActor @Sendable (Value) -> Void) -> Void,
    ) async -> Value {
        await withCheckedContinuation { continuation in
            let once = OnceContinuation(continuation)
            once.timer = Task {
                try? await Task.sleep(for: timeout)
                once.resume(fallback)
            }
            start { once.resume($0) }
        }
    }
}

/// Continuation resumed only once: by the answer or by the deadline, whichever comes first.
@MainActor
private final class OnceContinuation<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    var timer: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        timer?.cancel()
        timer = nil
        continuation.resume(returning: value)
    }
}
