import Foundation
import Observation

/// The windows' selections in a Space (`TabViewer`, review CO2): the active one, those of the windows that show or
/// showed this Space, and which window shows each tab. Held by its `TabManager`, which decides the moves
/// (`TabManager+Selection`).
@MainActor
@Observable
final class TabViewers {
    /// Viewer the tab actions apply to (selection, new tabs, Peek): that of the window in front showing this Space.
    /// The first one holds the restored selection until a window takes it.
    private(set) var active = TabViewer()
    /// The viewers of the windows that show or showed this Space, the active one included.
    @ObservationIgnored private(set) var all: [TabViewer] = []
    /// Which window shows each tab: the session's, shared by its Spaces and its windows of their own tabs (review ON2);
    /// this Space's own otherwise (tests).
    @ObservationIgnored var displays = TabDisplayRegistry() {
        didSet { all.forEach(displays.register) }
    }

    func contains(_ viewer: TabViewer) -> Bool {
        all.contains { $0 === viewer }
    }

    /// Makes `viewer` the active one.
    func setActive(_ viewer: TabViewer) {
        active = viewer
    }

    /// `viewer` now belongs to this Space.
    func adopt(_ viewer: TabViewer) {
        all.append(viewer)
        displays.register(viewer)
    }

    /// Forgets `viewer` (never the active one).
    func forget(_ viewer: TabViewer) {
        all.removeAll { $0 === viewer }
    }
}
