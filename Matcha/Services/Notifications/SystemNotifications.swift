import Foundation
import OSLog
import UserNotifications

/// A notification as macOS shows it. Pure type.
nonisolated struct SystemNotification: Equatable, Sendable {
    /// A new notification with the same identifier replaces the previous one.
    let identifier: String
    let title: String
    /// The website, as Safari shows it.
    let subtitle: String
    let body: String
    /// Groups the notifications of a website in the notification center.
    let threadIdentifier: String
    let isSilent: Bool
}

/// Notifications of macOS (`UserNotificationsBridge`); a fake in the tests.
@MainActor
protocol SystemNotifications: AnyObject {
    /// Receives the identifier of a notification the user clicked.
    var onActivate: (@MainActor (String) -> Void)? { get set }
    /// Asks macOS once whether Matcha may show notifications; true if it may.
    func requestAuthorization() async -> Bool
    func add(_ notification: SystemNotification) async throws
    func removeDelivered(_ identifiers: [String])
}

/// `UNUserNotificationCenter`: shows the notifications, even while Matcha is in front (as Safari does), and reports
/// clicks. Made once at launch (`AppEnvironment`), before a click that launches the app is delivered.
@MainActor
final class UserNotificationsBridge: NSObject, SystemNotifications {
    var onActivate: (@MainActor (String) -> Void)?
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                Logger.notifications.error("Authorization not requested: \(error.logSummary, privacy: .public)")
                return false
            }
        default:
            return false
        }
    }

    func add(_ notification: SystemNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.subtitle
        content.body = notification.body
        content.threadIdentifier = notification.threadIdentifier
        content.sound = notification.isSilent ? nil : .default
        try await center.add(UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil))
    }

    func removeDelivered(_ identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func activate(_ identifier: String) {
        onActivate?(identifier)
    }
}

extension UserNotificationsBridge: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            return
        }
        let identifier = response.notification.request.identifier
        await activate(identifier)
    }
}
