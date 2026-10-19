import Foundation

/// Remembered decision of a profile for an origin and a permission.
nonisolated struct SitePermissionEntry: Hashable, Identifiable, Sendable {
    struct Key: Hashable, Sendable {
        let profileID: UUID?
        let origin: SiteOrigin
        let kind: SitePermissionKind
    }

    let key: Key
    var decision: SitePermissionDecision
    var date: Date

    var id: Key {
        key
    }

    var profileID: UUID? {
        key.profileID
    }

    var origin: SiteOrigin {
        key.origin
    }

    var kind: SitePermissionKind {
        key.kind
    }
}
