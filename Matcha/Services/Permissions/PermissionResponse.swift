import Foundation
import Synchronization

/// Réponse attendue par WebKit pour une demande de permission (tâche 5.2), donnée une seule fois. Libérée sans
/// réponse (onglet ou fenêtre privée fermés pendant que le bandeau attend), elle refuse : WebKit lève une exception
/// quand le gestionnaire qu'il a confié n'est jamais appelé.
final nonisolated class PermissionResponse: Sendable {
    private let handler: @MainActor @Sendable (Bool) -> Void
    private let isAnswered = Mutex(false)

    /// `handler` reçoit vrai pour accorder, faux pour refuser.
    init(_ handler: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.handler = handler
    }

    var hasAnswered: Bool {
        isAnswered.withLock { $0 }
    }

    /// Accorde ou refuse ; sans effet après la première réponse.
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
