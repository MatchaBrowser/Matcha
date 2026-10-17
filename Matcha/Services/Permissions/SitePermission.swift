import Foundation

/// Permission qu'une page demande et dont la décision se retient par site (tâche 5.2). La localisation (API publique
/// à partir de macOS 27 seulement) et les notifications (aucune API publique) sont reportées : `DECISIONS.md`.
nonisolated enum SitePermissionKind: String, CaseIterable, Identifiable, Sendable {
    case camera
    case microphone

    var id: String {
        rawValue
    }
}

/// Décision retenue pour un site.
nonisolated enum SitePermissionDecision: String, CaseIterable, Sendable {
    case allow
    case deny
}

/// Réponse de l'utilisateur dans le bandeau de la page.
nonisolated enum SitePermissionAnswer: Sendable {
    /// Accordé pour cette demande seulement (WebKit le garde le temps de la page) ; rien n'est retenu.
    case allowOnce
    case alwaysAllow
    /// Refusé, et retenu (« Refuser »).
    case deny
}
