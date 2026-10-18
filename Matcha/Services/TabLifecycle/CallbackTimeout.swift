import Foundation

/// Attend la réponse d'une API à rappel (WebKit) au plus `timeout` : sans réponse à temps, `fallback`. Une réponse
/// arrivée après le délai est ignorée. Le rappel peut ne jamais venir (processus de la page bloqué).
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

/// Continuation reprise une seule fois : par la réponse ou par le délai, le premier des deux.
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
