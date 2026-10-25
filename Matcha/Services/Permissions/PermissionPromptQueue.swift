import Foundation
import Observation
import OSLog

/// Pending requests of a page (tab, Peek or mini window), shown one at a time in its banner, in order of arrival.
/// Without an answer, the page waits: nothing is granted or denied on its own. A new document in the page, or the page
/// closed, denies what is pending (`denyAll`). A website's requests to do something (open another app, download files:
/// audits W2 and W7) come after the permission requests; a page can't pile up the same one.
@MainActor
@Observable
final class PermissionPromptQueue {
    private(set) var requests: [SitePermissionRequest] = []
    private(set) var actions: [SiteActionRequest] = []
    /// When the user last refused each request to do something, in this document (review WB23).
    @ObservationIgnored private var declined: [SiteAction: Date] = [:]

    /// Displayed permission request.
    var current: SitePermissionRequest? {
        requests.first
    }

    /// Displayed request to do something, once the permission requests are answered.
    var currentAction: SiteActionRequest? {
        actions.first
    }

    /// True if the banner is waiting for an answer.
    var hasPending: Bool {
        current != nil || currentAction != nil
    }

    func enqueue(_ request: SitePermissionRequest) {
        requests.append(request)
    }

    /// True if a request for exactly `kinds` from `origin` is waiting (review WB2).
    func isAsking(_ kinds: Set<SitePermissionKind>, origin: SiteOrigin) -> Bool {
        requests.contains { $0.origin == origin && $0.requested == kinds }
    }

    /// False if the same request is already waiting: it is dropped.
    @discardableResult
    func enqueue(_ request: SiteActionRequest) -> Bool {
        guard !isWaiting(for: request.action) else {
            return false
        }
        actions.append(request)
        return true
    }

    func isWaiting(for action: SiteAction) -> Bool {
        actions.contains { $0.action == action }
    }

    /// When the user refused `action` in this document; nil if they didn't.
    func declineDate(of action: SiteAction) -> Date? {
        declined[action]
    }

    /// Answer from the banner to the displayed request to do something; “Always” is remembered for the website.
    func answerAction(_ answer: SiteActionAnswer) {
        guard !actions.isEmpty else {
            return
        }
        let request = actions.removeFirst()
        Logger.permissions.info("Request \(request.action.key, privacy: .public): \(String(describing: answer), privacy: .public)")
        if answer == .alwaysAllow, let origin = request.origin, let scope = request.scope {
            scope.allow(request.action, origin: origin)
        }
        if answer == .decline {
            declined[request.action] = .now
            request.decline()
        } else {
            request.perform()
        }
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
        Logger.permissions.info("Request \(granted ? "granted" : "denied", privacy: .public) from the banner")
        request.response.send(granted)
        resolveDecided()
    }

    /// Denies everything that is pending: the page changed document or is closing.
    func denyAll() {
        declined = [:]
        let pendingActions = actions
        actions = []
        pendingActions.forEach { $0.decline() }
        guard !requests.isEmpty else {
            return
        }
        let pending = requests
        requests = []
        Logger.permissions.info("\(pending.count, privacy: .public) request(s) denied: page left")
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
