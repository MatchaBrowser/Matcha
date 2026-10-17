import Foundation

/// Règles des demandes de permission (tâche 5.2), sans WebKit ni interface.
nonisolated enum SitePermissionPolicy {
    enum Outcome: Equatable, Sendable {
        /// Décisions retenues : accordé sans rien demander.
        case grant
        /// Une décision retenue refuse : refusé sans rien demander.
        case deny
        /// Le bandeau demande ces permissions, celles sans décision retenue.
        case ask(Set<SitePermissionKind>)
    }

    /// Une permission demandée et refusée l'emporte (WebKit accorde ou refuse la demande en entier) ; toutes
    /// autorisées : accordé ; sinon, on demande celles qui n'ont pas de décision. Une demande vide est refusée.
    static func evaluate(
        _ requested: Set<SitePermissionKind>,
        stored: [SitePermissionKind: SitePermissionDecision],
    ) -> Outcome {
        guard !requested.isEmpty, !requested.contains(where: { stored[$0] == .deny }) else {
            return .deny
        }
        let undecided = requested.filter { stored[$0] == nil }
        return undecided.isEmpty ? .grant : .ask(undecided)
    }

    /// Réponse transmise à WebKit.
    static func grants(_ answer: SitePermissionAnswer) -> Bool {
        answer != .deny
    }

    /// Décisions à retenir pour les permissions `asked` : aucune pour « Autoriser une fois ».
    static func decisionsToStore(
        for answer: SitePermissionAnswer,
        asked: Set<SitePermissionKind>,
    ) -> [SitePermissionKind: SitePermissionDecision] {
        switch answer {
        case .allowOnce:
            [:]
        case .alwaysAllow:
            Dictionary(uniqueKeysWithValues: asked.map { ($0, .allow) })
        case .deny:
            Dictionary(uniqueKeysWithValues: asked.map { ($0, .deny) })
        }
    }
}
