import Foundation

/// Models of a browser window, made once (audit R5). SwiftUI evaluates the initial value of a `@State` each time it
/// recreates the view, then keeps the first one: this holder costs nothing to make, and the models are only made when
/// first read.
@MainActor
final class WindowModels {
    private let session: BrowserSession

    init(session: BrowserSession) {
        self.session = session
    }

    /// The displayed Space is remembered from one launch to the next, except with a test store.
    lazy var window = WindowModel(session: session, defaults: session.isInMemory ? nil : .standard)

    /// History of the displayed Space's profile, reread on each keystroke; none for a private window.
    lazy var commandBar: CommandBarModel = {
        let window = window
        let history = session.history.map { store in ProfileHistory(store: store) { window.space.record.profile?.id } }
        return CommandBarModel(windowModel: window, history: history)
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
