import Foundation

/// A notification a page asks to show (`new Notification(title, options)`), as macOS shows it. Pure type.
nonisolated struct PageNotificationContent: Equatable, Sendable {
    /// Longest title and text kept: a page can't fill the notification center.
    static let maximumTitleLength = 200
    static let maximumBodyLength = 1000

    /// Identifier given by the page's script, to send it the notification's events back (click).
    let scriptID: String
    let title: String
    let body: String
    /// A new notification with the same tag replaces the previous one; empty: none.
    let tag: String
    /// Shown without sound.
    let isSilent: Bool

    init(scriptID: String, title: String, body: String = "", tag: String = "", isSilent: Bool = false) {
        self.scriptID = scriptID
        self.title = String(title.prefix(Self.maximumTitleLength))
        self.body = String(body.prefix(Self.maximumBodyLength))
        self.tag = String(tag.prefix(Self.maximumTitleLength))
        self.isSilent = isSilent
    }
}

/// Message of the notification script of a page (`PageNotificationScript`) to the app. Pure type.
nonisolated enum PageNotificationMessage: Equatable, Sendable {
    /// `Notification.requestPermission()`, right after a click or a key press in the page.
    case requestPermission
    case show(PageNotificationContent)
    /// `notification.close()`.
    case close(scriptID: String)

    /// Reads the body of a script message; nil if it is malformed.
    init?(body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else {
            return nil
        }
        switch type {
        case "request":
            self = .requestPermission
        case "show":
            guard let id = message["id"] as? String, !id.isEmpty, let title = message["title"] as? String else {
                return nil
            }
            self = .show(PageNotificationContent(
                scriptID: id,
                title: title,
                body: message["body"] as? String ?? "",
                tag: message["tag"] as? String ?? "",
                isSilent: message["silent"] as? Bool ?? false,
            ))
        case "close":
            guard let id = message["id"] as? String, !id.isEmpty else {
                return nil
            }
            self = .close(scriptID: id)
        default:
            return nil
        }
    }
}

/// Permission as the pages read it (`Notification.permission`). Pure type.
nonisolated enum PageNotificationPermission: String, Sendable {
    case granted
    case denied
    /// Not decided yet: the page may ask.
    case `default`

    init(_ decision: SitePermissionDecision?) {
        switch decision {
        case .allow: self = .granted
        case .deny: self = .denied
        case nil: self = .default
        }
    }
}
