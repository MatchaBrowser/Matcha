import Foundation

/// A `NotificationCenter` observer, on the main queue, removed when this object goes away, whatever the thread that
/// releases its owner: the owner needs no `deinit`. For `NSObject` subclasses, which can't use `isolated deinit`:
/// built by Xcode 26's compiler, it checks the main actor instead of going to it, and crashes when the last reference
/// goes away elsewhere (unit tests on the CI, 2026-10-21).
final nonisolated class NotificationObservation {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    init(
        of name: Notification.Name,
        object: Any? = nil,
        center: NotificationCenter = .default,
        using block: @escaping @Sendable (Notification) -> Void,
    ) {
        self.center = center
        token = center.addObserver(forName: name, object: object, queue: .main, using: block)
    }

    deinit {
        center.removeObserver(token)
    }
}
