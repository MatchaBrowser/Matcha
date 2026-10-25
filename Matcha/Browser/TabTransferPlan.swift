import Foundation

/// What happens to a tab dropped from one Space or window of the session into another (review ON6). Pure type.
nonisolated enum TabTransferPlan: Equatable, Sendable {
    /// Same profile: the tab itself moves, with its page and its history.
    case move
    /// Same profile, a favorite or a pinned tab dropped into a window of its own tabs: it stays in its sidebar, the
    /// window gets a copy with its history.
    case copy
    /// Other profile: recreated from its address, with that profile's cookies; the original goes away, unless it is a
    /// favorite or a pinned tab dropped into a window of its own tabs.
    case recreate(keepsSource: Bool)

    /// `sameProfile`: same data store, so same cookies (one store per profile).
    static func plan(sameProfile: Bool, sourcePlace: TabPlace?, intoWindowTabs: Bool) -> TabTransferPlan {
        let keepsSource = intoWindowTabs && sourcePlace != .today
        guard sameProfile else {
            return .recreate(keepsSource: keepsSource)
        }
        return keepsSource ? .copy : .move
    }
}
