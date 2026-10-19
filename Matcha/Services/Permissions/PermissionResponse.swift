import Foundation
import Synchronization

/// Answer expected by WebKit for a permission request (task 5.2), given only once. Released without an answer (tab or
/// private window closed while the banner waits), it denies: WebKit raises an exception when the handler it handed over
/// is never called.
final nonisolated class PermissionResponse: Sendable {
    private let handler: @MainActor @Sendable (Bool) -> Void
    private let isAnswered = Mutex(false)

    /// `handler` receives true to grant, false to deny.
    init(_ handler: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.handler = handler
    }

    var hasAnswered: Bool {
        isAnswered.withLock { $0 }
    }

    /// Grants or denies; no effect after the first answer.
    @MainActor
    func send(_ granted: Bool) {
        let isFirst = isAnswered.withLock { answered in
            defer { answered = true }
            return !answered
        }
        if isFirst {
            handler(granted)
        }
    }

    deinit {
        guard !isAnswered.withLock({ $0 }) else {
            return
        }
        let handler = handler
        Task { @MainActor in handler(false) }
    }
}
