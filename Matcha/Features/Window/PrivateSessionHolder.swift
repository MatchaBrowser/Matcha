import Foundation

/// The session of a private window, made once, when the window first shows (audit R5).
@MainActor
final class PrivateSessionHolder {
    private let services: SessionServices
    lazy var session = BrowserSession.makePrivate(services: services)

    init(services: SessionServices) {
        self.services = services
    }
}
