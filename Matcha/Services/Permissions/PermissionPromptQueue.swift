import Foundation
import Observation
import OSLog

/// Permission request waiting for the user's answer in the banner of the page that made it.
struct SitePermissionRequest: Identifiable {
    let id = UUID()
    /// Origin of the main page; nil if it cannot be remembered (page without a host: local file…).
    let origin: SiteOrigin?
    /// Website of the requesting frame, if it is not the page's (embedded frame).
    let frameName: String?
    /// Permissions requested by the page.
    let requested: Set<SitePermissionKind>
    /// Those that the banner asks for: without a remembered decision.
    let asked: Set<SitePermissionKind>
    /// Where to remember the answer; nil: nowhere.
    let scope: SitePermissionScope?
    let response: PermissionResponse

    /// “Always Allow” is offered only if the decision can be remembered.
    var canRemember: Bool {
        origin != nil && scope != nil
    }
}

/// Pending requests of a page (tab, Peek or mini window), shown one at a time in its banner, in order of arrival.
/// Without an answer, the page waits: nothing is granted or denied on its own. A new document in the page, or the page
/// closed, denies what is pending (`denyAll`).
@MainActor
@Observable
final class PermissionPromptQueue {
    private(set) var requests: [SitePermissionRequest] = []

    /// Displayed request.
    var current: SitePermissionRequest? {
        requests.first
    }

    func enqueue(_ request: SitePermissionRequest) {
        requests.append(request)
    }

    /// Answer from the banner: the displayed request receives it and the decision is remembered if appropriate; the
    /// following ones that this decision settles leave too.
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

    /// Denies everything that is pending: the page changed document or is closing.
    func denyAll() {
        guard !requests.isEmpty else {
            return
        }
        let pending = requests
        requests = []
        Logger.permissions.info("\(pending.count, privacy: .public) demande(s) refusée(s) : page quittée")
        pending.forEach { $0.response.send(false) }
    }

    /// Answers the pending requests that a remembered decision now settles.
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
