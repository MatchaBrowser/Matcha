import Foundation
import Observation
import OSLog

/// Demande de permission qui attend la réponse de l'utilisateur dans le bandeau de la page qui l'a faite.
struct SitePermissionRequest: Identifiable {
    let id = UUID()
    /// Origine de la page principale ; nil si elle ne peut pas être retenue (page sans hôte : fichier local…).
    let origin: SiteOrigin?
    /// Site du cadre qui demande, s'il n'est pas celui de la page (cadre intégré).
    let frameName: String?
    /// Permissions demandées par la page.
    let requested: Set<SitePermissionKind>
    /// Celles que le bandeau demande : sans décision retenue.
    let asked: Set<SitePermissionKind>
    /// Où retenir la réponse ; nil : nulle part.
    let scope: SitePermissionScope?
    let response: PermissionResponse

    /// « Toujours autoriser » n'est proposé que si la décision peut être retenue.
    var canRemember: Bool {
        origin != nil && scope != nil
    }
}

/// Demandes en attente d'une page (onglet, aperçu ou mini-fenêtre), montrées une à une dans son bandeau, dans
/// l'ordre d'arrivée. Sans réponse, la page attend : rien n'est accordé ni refusé de soi-même. Un nouveau document
/// dans la page, ou la page fermée, refuse ce qui attend (`denyAll`).
@MainActor
@Observable
final class PermissionPromptQueue {
    private(set) var requests: [SitePermissionRequest] = []

    /// Demande affichée.
    var current: SitePermissionRequest? {
        requests.first
    }

    func enqueue(_ request: SitePermissionRequest) {
        requests.append(request)
    }

    /// Réponse au bandeau : la demande affichée la reçoit et la décision est retenue s'il y a lieu ; les suivantes que
    /// cette décision tranche partent aussi.
    func answer(_ answer: SitePermissionAnswer) {
        guard !requests.isEmpty else {
            return
        }
        let request = requests.removeFirst()
        if let origin = request.origin, let scope = request.scope {
            for (kind, decision) in SitePermissionPolicy.decisionsToStore(for: answer, asked: request.asked) {
                scope.set(decision, for: kind, origin: origin)
            }
        }
        let granted = SitePermissionPolicy.grants(answer)
        Logger.permissions.info("Demande \(granted ? "accordée" : "refusée", privacy: .public) depuis le bandeau")
        request.response.send(granted)
        resolveDecided()
    }

    /// Refuse tout ce qui attend : la page a changé de document ou se ferme.
    func denyAll() {
        guard !requests.isEmpty else {
            return
        }
        let pending = requests
        requests = []
        Logger.permissions.info("\(pending.count, privacy: .public) demande(s) refusée(s) : page quittée")
        pending.forEach { $0.response.send(false) }
    }

    /// Répond aux demandes en attente qu'une décision retenue tranche désormais.
    private func resolveDecided() {
        var remaining: [SitePermissionRequest] = []
        for request in requests {
            guard let origin = request.origin, let scope = request.scope else {
                remaining.append(request)
                continue
            }
            switch SitePermissionPolicy.evaluate(request.requested, stored: scope.decisions(for: origin)) {
            case .grant:
                request.response.send(true)
            case .deny:
                request.response.send(false)
            case .ask:
                remaining.append(request)
            }
        }
        requests = remaining
    }
}
