import Foundation

/// What a browser window opens on and restores at the next launch: its displayed Space, and its own tabs (a detached
/// tab, `WindowTabs`; not found after a relaunch: the window shows the Space). Unique per window: SwiftUI brings to the
/// front the window opened with a value equal to that of an open window.
nonisolated struct BrowserWindowState: Codable, Hashable, Sendable {
    var id = UUID()
    var spaceID: UUID?
    /// The window's own tabs (“Open in New Window”, tab dragged out of the window).
    var windowTabsID: UUID?
    /// Where to place the window's top left corner at opening, in screen coordinates (tab dragged out of the window).
    var origin: CGPoint?
    /// Opened during use (⌘N, “Open in New Window”): placed just below and to the right of the front window, at its
    /// size, rather than on top of it. Never for a window restored at launch.
    var cascades = false

    init(spaceID: UUID? = nil, windowTabsID: UUID? = nil, origin: CGPoint? = nil, cascades: Bool = false) {
        self.spaceID = spaceID
        self.windowTabsID = windowTabsID
        self.origin = origin
        self.cascades = cascades
    }

    /// Lenient: a state saved by an earlier version lacks the newer fields.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        spaceID = try container.decodeIfPresent(UUID.self, forKey: .spaceID)
        windowTabsID = try container.decodeIfPresent(UUID.self, forKey: .windowTabsID)
        origin = try container.decodeIfPresent(CGPoint.self, forKey: .origin)
        cascades = try container.decodeIfPresent(Bool.self, forKey: .cascades) ?? false
    }
}
