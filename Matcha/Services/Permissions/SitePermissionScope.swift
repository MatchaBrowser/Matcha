import Foundation
import Observation
import OSLog
import SwiftData

/// Decisions seen by the pages of a profile: those of a Space, of its Peek or of a mini window.
struct SitePermissionScope {
    let store: SitePermissionStore
    let profileID: UUID?

    func decisions(for origin: SiteOrigin) -> [SitePermissionKind: SitePermissionDecision] {
        store.decisions(for: origin, profileID: profileID)
    }

    func decision(_ kind: SitePermissionKind, for origin: SiteOrigin) -> SitePermissionDecision? {
        store.decision(kind, for: origin, profileID: profileID)
    }

    func set(_ decision: SitePermissionDecision?, for kind: SitePermissionKind, origin: SiteOrigin) {
        store.set(decision, for: kind, origin: origin, profileID: profileID)
    }

    func isAllowed(_ action: SiteAction, origin: SiteOrigin) -> Bool {
        store.actions.isAllowed(action, origin: origin, profileID: profileID)
    }

    func allow(_ action: SiteAction, origin: SiteOrigin) {
        store.actions.allow(action, origin: origin, profileID: profileID)
    }

    /// Actions allowed for `origin`, in the site settings.
    func actions(for origin: SiteOrigin) -> [SiteActionAllowances.Entry] {
        store.actions.actions(for: origin, profileID: profileID)
    }
}
