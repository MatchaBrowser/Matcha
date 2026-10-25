import Foundation

/// Models of a browser window, made once (audit R5). SwiftUI evaluates the initial value of a `@State` each time it
/// recreates the view, then keeps the first one: this holder costs nothing to make, and the models are only made when
/// first read.
@MainActor
final class WindowModels {
    private let session: BrowserSession
    /// Space the window opens on (restored window, new window); nil: the last displayed one.
    private let spaceID: UUID?
    /// The window's own tabs (detached tab).
    private let windowTabsID: UUID?

    init(session: BrowserSession, spaceID: UUID? = nil, windowTabsID: UUID? = nil) {
        self.session = session
        self.spaceID = spaceID
        self.windowTabsID = windowTabsID
    }

    /// The last displayed Space is remembered from one launch to the next, except with a test store.
    lazy var window = WindowModel(
        session: session,
        defaults: session.isInMemory ? nil : .standard,
        spaceID: spaceID,
        windowTabs: session.windowTabs(withID: windowTabsID),
    )

    /// History of the displayed Space's profile, reread on each keystroke; none for a private window.
    lazy var commandBar: CommandBarModel = {
        let window = window
        let history = session.history.map { store in ProfileHistory(store: store) { window.space.record.profile?.id } }
        return CommandBarModel(windowModel: window, history: history, otherMacs: session.services.otherMacs)
    }()
}

/// The session of a private window, made once, when the window first shows (audit R5).
@MainActor
final class PrivateSessionHolder {
    private let services: SessionServices
    lazy var session = BrowserSession.makePrivate(services: services)

    init(services: SessionServices) {
        self.services = services
    }
}
