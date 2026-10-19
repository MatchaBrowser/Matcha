import Foundation

/// Space where “Open in Space” sends a mini window's page, with no dependency on the interface.
nonisolated enum MiniWindowTarget {
    /// What the rule knows about a Space.
    struct Space: Equatable, Sendable {
        let id: UUID
        let profileID: UUID?
    }

    /// Target Space (“Open in …” button, ⇧⌘O, ⌘-click) for a page of profile `profileID`:
    /// 1. the Space displayed by the main window, if it belongs to that profile (Arc's “most recent”);
    /// 2. otherwise the first Space of that profile, in the sidebar's order;
    /// 3. otherwise (no Space of that profile left) the displayed Space, then the first Space.
    /// Nil only without any Space.
    static func defaultSpaceID(profileID: UUID?, displayedSpaceID: UUID?, spaces: [Space]) -> UUID? {
        let displayed = spaces.first { $0.id == displayedSpaceID }
        if let displayed, displayed.profileID == profileID {
            return displayed.id
        }
        if let sameProfile = spaces.first(where: { $0.profileID == profileID }) {
            return sameProfile.id
        }
        return displayed?.id ?? spaces.first?.id
    }
}
